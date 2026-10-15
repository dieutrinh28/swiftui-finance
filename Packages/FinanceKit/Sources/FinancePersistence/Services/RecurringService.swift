import Foundation
import SwiftData
import FinanceDomain

public struct RecurringDraft {
    public var name: String
    public var kind: TransactionKind
    /// Unsigned, in the (source) wallet's currency.
    public var amount: Money
    /// The wallet of an income/expense, or the source of a transfer.
    public var wallet: Wallet
    /// Required for income and expenses; ignored for transfers.
    public var category: LedgerCategory?
    /// Transfers only: the receiving wallet.
    public var destination: Wallet?
    /// Transfers between currencies only: the unsigned amount arriving in
    /// `destination`, in its currency. Ignored when the currencies match.
    public var receivedAmount: Money?
    public var schedule: RecurrenceSchedule
    public var note: String?
    public var reminderEnabled: Bool
    public var reminderMinutes: Int

    public init(
        name: String,
        kind: TransactionKind,
        amount: Money,
        wallet: Wallet,
        category: LedgerCategory?,
        destination: Wallet? = nil,
        receivedAmount: Money? = nil,
        schedule: RecurrenceSchedule,
        note: String? = nil,
        reminderEnabled: Bool = false,
        reminderMinutes: Int = 9 * 60
    ) {
        self.name = name
        self.kind = kind
        self.amount = amount
        self.wallet = wallet
        self.category = category
        self.destination = destination
        self.receivedAmount = receivedAmount
        self.schedule = schedule
        self.note = note
        self.reminderEnabled = reminderEnabled
        self.reminderMinutes = reminderMinutes
    }
}

/// An occurrence that is due (on or before today) and not yet recorded or skipped.
/// Why a recurring item produces nothing for now. Archiving keeps history
/// read-only, so a definition that would record into an archived wallet or
/// category is held instead of offering occurrences that can't be recorded.
/// Restoring the wallet/category, or editing the item, lifts the hold.
public enum RecurringHold {
    case archivedWallet(Wallet)
    case archivedCategory(LedgerCategory)
}

/// An occurrence marked handled without a transaction: skipped by the user,
/// or passed over when the schedule changed.
public struct SkippedOccurrence: Identifiable {
    public let key: String
    public let day: DayKey
    public let date: Date
    public var id: String { key }

    public init(key: String, day: DayKey, date: Date) {
        self.key = key
        self.day = day
        self.date = date
    }
}

public struct DueOccurrence: Identifiable {
    public let recurring: RecurringTransaction
    public let occurrence: Occurrence
    public let key: String

    public var id: String { key }
}

/// A reminder to schedule with the system.
public struct PlannedReminder: Sendable, Equatable, Identifiable {
    /// Stable identifier, derived from the occurrence key.
    public let id: String
    public let fireDate: Date
    public let title: String
    public let amount: Money
    public let kind: TransactionKind
}

/// Recurring income, expense and transfer definitions and their occurrences.
///
/// No background work: `dueOccurrences(at:)` is evaluated when the app runs.
/// Recording an occurrence inserts the transaction (tagged with its occurrence
/// key) and marks the key handled in one save, so it can't be recorded twice.
public struct RecurringService {
    /// Upper bound on occurrences offered at once (e.g. a daily item backdated by years).
    public static let dueLimit = 100

    private let context: ModelContext
    private let calendar: CalendarPolicy
    private let transactions: TransactionService
    private let now: () -> Date

    public init(context: ModelContext, calendar: CalendarPolicy = CalendarPolicy(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.calendar = calendar
        self.now = now
        self.transactions = TransactionService(context: context, calendar: calendar, now: now)
    }

    // MARK: Definitions

    @discardableResult
    public func create(_ draft: RecurringDraft) throws -> RecurringTransaction {
        let (name, links) = try validate(draft)
        let recurring = RecurringTransaction(
            name: name,
            kind: draft.kind,
            amount: draft.amount,
            walletID: draft.wallet.id,
            categoryID: links.categoryID,
            destinationWalletID: links.destinationWalletID,
            receivedAmountMinorUnits: links.receivedAmountMinorUnits,
            schedule: normalized(draft.schedule),
            note: TextRules.optionalText(draft.note),
            reminderEnabled: draft.reminderEnabled,
            reminderMinutes: draft.reminderMinutes,
            sortOrder: try nextSortOrder(),
            createdAt: now()
        )
        context.insert(recurring)
        try context.saveOrRollback()
        return recurring
    }

    /// Editing changes future occurrences only; recorded transactions are untouched.
    ///
    /// When the schedule changes, occurrences of the new schedule before
    /// today are marked handled: they were never due under the old schedule,
    /// so offering them as "due" (and possibly recording them twice) would be
    /// wrong. Today's occurrence, if any, stays due.
    public func update(_ recurring: RecurringTransaction, with draft: RecurringDraft) throws {
        let (name, links) = try validate(draft)
        let schedule = normalized(draft.schedule)
        if schedule != recurring.schedule {
            let today = calendar.calendar.startOfDay(for: now())
            if let yesterday = calendar.calendar.date(byAdding: .day, value: -1, to: today), yesterday >= schedule.startDate {
                var handled = recurring.handledOccurrenceKeys
                var known = Set(handled)
                for occurrence in RecurrenceRules.occurrences(
                    of: schedule, from: schedule.startDate, through: yesterday, policy: calendar, limit: 10_000
                ) {
                    let key = RecurrenceRules.occurrenceKey(recurringID: recurring.id, day: occurrence.day)
                    if known.insert(key).inserted { handled.append(key) }
                }
                recurring.handledOccurrenceKeys = handled
            }
        }
        recurring.name = name
        recurring.kindRaw = draft.kind.rawValue
        recurring.amountMinorUnits = draft.amount.minorUnits
        recurring.currencyCode = draft.amount.currency.code
        recurring.walletID = draft.wallet.id
        recurring.categoryID = links.categoryID
        recurring.destinationWalletID = links.destinationWalletID
        recurring.receivedAmountMinorUnits = links.receivedAmountMinorUnits
        recurring.frequencyRaw = schedule.frequency.rawValue
        recurring.interval = schedule.interval
        recurring.startDate = schedule.startDate
        recurring.endDate = schedule.endDate
        recurring.note = TextRules.optionalText(draft.note)
        recurring.reminderEnabled = draft.reminderEnabled
        recurring.reminderMinutes = draft.reminderMinutes
        recurring.updatedAt = now()
        try context.saveOrRollback()
    }

    public func setPaused(_ recurring: RecurringTransaction, _ paused: Bool) throws {
        recurring.pausedAt = paused ? now() : nil
        recurring.updatedAt = now()
        try context.saveOrRollback()
    }

    /// Deletes the definition. Transactions already recorded from it stay.
    public func delete(_ recurring: RecurringTransaction) throws {
        context.delete(recurring)
        try context.saveOrRollback()
    }

    // MARK: Occurrences

    /// Occurrences on or before `reference`'s day that are not handled yet, oldest first.
    public func dueOccurrences(at reference: Date) throws -> [DueOccurrence] {
        let definitions = try context.fetch(FetchDescriptor<RecurringTransaction>(sortBy: [SortDescriptor(\.sortOrder)]))
        var result: [DueOccurrence] = []
        let archived = try archivedReferences()
        for recurring in definitions where !recurring.isPaused && !archived.holds(recurring) {
            guard let schedule = recurring.schedule else { continue }
            let handled = Set(recurring.handledOccurrenceKeys)
            let occurrences = RecurrenceRules.occurrences(
                of: schedule, from: schedule.startDate, through: reference, policy: calendar, limit: 10_000
            )
            for occurrence in occurrences {
                let key = RecurrenceRules.occurrenceKey(recurringID: recurring.id, day: occurrence.day)
                if !handled.contains(key) {
                    result.append(DueOccurrence(recurring: recurring, occurrence: occurrence, key: key))
                }
            }
        }
        return Array(result.sorted { $0.occurrence.date < $1.occurrence.date }.prefix(Self.dueLimit))
    }

    /// The next not-yet-handled occurrence of each active definition within
    /// `days` days, soonest first. An occurrence recorded or skipped early is
    /// not shown again.
    public func upcoming(from reference: Date, days: Int) throws -> [(recurring: RecurringTransaction, occurrence: Occurrence)] {
        guard let horizon = calendar.calendar.date(byAdding: .day, value: days, to: reference) else { return [] }
        let definitions = try context.fetch(FetchDescriptor<RecurringTransaction>())
        let archived = try archivedReferences()
        return definitions
            .filter { !$0.isPaused && !archived.holds($0) }
            .compactMap { recurring -> (recurring: RecurringTransaction, occurrence: Occurrence)? in
                guard let schedule = recurring.schedule else { return nil }
                let handled = Set(recurring.handledOccurrenceKeys)
                var cursor = reference
                // Skip handled occurrences; bounded by the horizon.
                while let next = RecurrenceRules.next(of: schedule, onOrAfter: cursor, policy: calendar),
                      next.date <= horizon {
                    let key = RecurrenceRules.occurrenceKey(recurringID: recurring.id, day: next.day)
                    if !handled.contains(key) { return (recurring, next) }
                    guard let after = calendar.calendar.date(byAdding: .day, value: 1,
                                                             to: calendar.calendar.startOfDay(for: next.date))
                    else { return nil }
                    cursor = after
                }
                return nil
            }
            .sorted { $0.occurrence.date < $1.occurrence.date }
    }

    /// Records a due occurrence as a transaction (optionally with a different
    /// amount, e.g. a variable bill) and marks it handled, in one save.
    ///
    /// Transfers: `amount` overrides the amount sent. Between currencies the
    /// received amount can't be derived from it, so overriding the sent
    /// amount also requires `received`.
    @discardableResult
    public func record(_ due: DueOccurrence, amount override: Money? = nil, received receivedOverride: Money? = nil) throws -> LedgerTransaction {
        let recurring = due.recurring
        guard !recurring.handledOccurrenceKeys.contains(due.key) else {
            throw LedgerValidationError.duplicateOccurrence
        }
        guard let kind = recurring.kind, let amount = override ?? recurring.amount,
              let wallet = try self.wallet(of: recurring)
        else { throw LedgerValidationError.corruptRecord }

        do {
            let transaction: LedgerTransaction
            if kind == .transfer {
                guard let destination = try self.destinationWallet(of: recurring) else {
                    throw LedgerValidationError.missingDestinationWallet
                }
                var received = receivedOverride
                if received == nil, destination.currencyCode != wallet.currencyCode {
                    guard override == nil else { throw LedgerValidationError.missingReceivedAmount }
                    received = try recurring.receivedAmount(in: destination)
                }
                transaction = try transactions.insertTransfer(TransferDraft(
                    source: wallet,
                    destination: destination,
                    sent: amount,
                    received: received,
                    date: due.occurrence.date,
                    note: recurring.note ?? recurring.name,
                    recurringOccurrenceKey: due.key
                ))
            } else {
                guard let category = try self.category(of: recurring) else { throw LedgerValidationError.corruptRecord }
                transaction = try transactions.insertCashFlow(CashFlowDraft(
                    kind: kind,
                    amount: amount,
                    wallet: wallet,
                    category: category,
                    date: due.occurrence.date,
                    note: recurring.note ?? recurring.name,
                    recurringOccurrenceKey: due.key
                ))
            }
            recurring.handledOccurrenceKeys.append(due.key)
            try context.saveOrRollback()
            return transaction
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Marks a due occurrence as handled without recording anything.
    public func skip(_ due: DueOccurrence) throws {
        guard !due.recurring.handledOccurrenceKeys.contains(due.key) else { return }
        due.recurring.handledOccurrenceKeys.append(due.key)
        try context.saveOrRollback()
    }

    /// Handled occurrences without a recorded transaction, newest first.
    public func skippedOccurrences(of recurring: RecurringTransaction, limit: Int = 10) throws -> [SkippedOccurrence] {
        let prefix = recurring.id.uuidString
        let recorded = Set(try context.fetch(FetchDescriptor<LedgerTransaction>())
            .compactMap(\.recurringOccurrenceKey)
            .filter { $0.hasPrefix(prefix) })
        return recurring.handledOccurrenceKeys
            .filter { !recorded.contains($0) }
            .compactMap { key -> SkippedOccurrence? in
                guard let parsed = RecurrenceRules.parseOccurrenceKey(key), parsed.recurringID == recurring.id,
                      let date = calendar.startOfDay(parsed.day)
                else { return nil }
                return SkippedOccurrence(key: key, day: parsed.day, date: date)
            }
            .sorted { $0.day > $1.day }
            .prefix(limit)
            .map { $0 }
    }

    /// Undoes a skip: the occurrence becomes due again (if its day has come).
    /// A recorded occurrence can't be reopened this way; delete its transaction instead.
    public func reopen(_ skipped: SkippedOccurrence, of recurring: RecurringTransaction) throws {
        let optionalKey: String? = skipped.key
        let recorded = try context.fetchCount(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.recurringOccurrenceKey == optionalKey }
        ))
        guard recorded == 0 else { throw LedgerValidationError.duplicateOccurrence }
        recurring.handledOccurrenceKeys.removeAll { $0 == skipped.key }
        recurring.updatedAt = now()
        try context.saveOrRollback()
    }

    /// Why this item produces nothing, if it is held (see `RecurringHold`).
    public func hold(of recurring: RecurringTransaction) throws -> RecurringHold? {
        for wallet in [try wallet(of: recurring), try destinationWallet(of: recurring)].compactMap({ $0 }) where wallet.isArchived {
            return .archivedWallet(wallet)
        }
        if let category = try category(of: recurring), category.isArchived {
            return .archivedCategory(category)
        }
        return nil
    }

    // MARK: Reminders

    /// Reminders for upcoming occurrences of definitions with reminders on,
    /// soonest first, at most `limit` (iOS keeps at most 64 pending).
    public func plannedReminders(after reference: Date, perDefinition: Int = 3, limit: Int = 60) throws -> [PlannedReminder] {
        let definitions = try context.fetch(FetchDescriptor<RecurringTransaction>())
        var reminders: [PlannedReminder] = []
        let archived = try archivedReferences()
        for recurring in definitions where recurring.reminderEnabled && !recurring.isPaused && !archived.holds(recurring) {
            guard let schedule = recurring.schedule, let amount = recurring.amount, let kind = recurring.kind else { continue }
            let handled = Set(recurring.handledOccurrenceKeys)
            for item in RecurrenceRules.reminderDates(
                of: schedule, minutesAfterMidnight: recurring.reminderMinutes,
                after: reference, count: perDefinition, policy: calendar
            ) {
                let key = RecurrenceRules.occurrenceKey(recurringID: recurring.id, day: item.occurrence.day)
                guard !handled.contains(key) else { continue }
                reminders.append(PlannedReminder(id: key, fireDate: item.fireDate, title: recurring.name, amount: amount, kind: kind))
            }
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    // MARK: Lookups

    public func wallet(of recurring: RecurringTransaction) throws -> Wallet? {
        let id = recurring.walletID
        return try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == id })).first
    }

    /// nil for transfers.
    public func category(of recurring: RecurringTransaction) throws -> LedgerCategory? {
        guard let id = recurring.categoryID else { return nil }
        return try context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.id == id })).first
    }

    /// The receiving wallet of a recurring transfer; nil otherwise.
    public func destinationWallet(of recurring: RecurringTransaction) throws -> Wallet? {
        guard let id = recurring.destinationWalletID else { return nil }
        return try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == id })).first
    }

    /// Transactions recorded from this definition, newest first.
    public func recordedTransactions(of recurring: RecurringTransaction) throws -> [LedgerTransaction] {
        let prefix = recurring.id.uuidString
        return try context.fetch(FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            .filter { $0.recurringOccurrenceKey?.hasPrefix(prefix) ?? false }
    }

    // MARK: Private

    /// Ids of archived wallets and categories, read once per query.
    private struct ArchivedReferences {
        let wallets: Set<UUID>
        let categories: Set<UUID>

        func holds(_ recurring: RecurringTransaction) -> Bool {
            wallets.contains(recurring.walletID)
                || recurring.destinationWalletID.map { wallets.contains($0) } == true
                || recurring.categoryID.map { categories.contains($0) } == true
        }
    }

    private func archivedReferences() throws -> ArchivedReferences {
        let wallets = try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.archivedAt != nil }))
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.archivedAt != nil }))
        return ArchivedReferences(wallets: Set(wallets.map(\.id)), categories: Set(categories.map(\.id)))
    }

    private struct Links {
        var categoryID: UUID?
        var destinationWalletID: UUID?
        var receivedAmountMinorUnits: Int64?
    }

    /// The same rules as recording the transaction now, so a definition that
    /// saves can also be recorded.
    private func validate(_ draft: RecurringDraft) throws -> (String, Links) {
        let name = try TextRules.normalizedName(draft.name)
        try RecurrenceRules.validate(draft.schedule, policy: calendar)
        guard (0..<(24 * 60)).contains(draft.reminderMinutes) else { throw LedgerValidationError.invalidRecurrence }
        guard let walletCurrency = draft.wallet.currency else { throw LedgerValidationError.corruptRecord }

        if draft.kind == .transfer {
            guard let destination = draft.destination else { throw LedgerValidationError.missingDestinationWallet }
            guard let destinationCurrency = destination.currency else { throw LedgerValidationError.corruptRecord }
            let sameCurrency = destinationCurrency == walletCurrency
            let received: Money
            if sameCurrency {
                received = draft.amount
            } else {
                guard let explicit = draft.receivedAmount else { throw LedgerValidationError.missingReceivedAmount }
                received = explicit
            }
            try LedgerRules.validateTransfer(TransferCandidate(
                sent: draft.amount,
                received: received,
                sourceCurrency: walletCurrency,
                destinationCurrency: destinationCurrency,
                isSameWallet: draft.wallet.id == destination.id,
                sourceIsArchived: draft.wallet.isArchived,
                destinationIsArchived: destination.isArchived
            ))
            return (name, Links(destinationWalletID: destination.id,
                                receivedAmountMinorUnits: sameCurrency ? nil : received.minorUnits))
        }

        guard let category = draft.category else { throw LedgerValidationError.missingCategory }
        guard let categoryType = category.type else { throw LedgerValidationError.corruptRecord }
        try LedgerRules.validateCashFlow(CashFlowCandidate(
            kind: draft.kind,
            amount: draft.amount,
            walletCurrency: walletCurrency,
            walletIsArchived: draft.wallet.isArchived,
            categoryType: categoryType,
            categoryIsArchived: category.isArchived
        ))
        return (name, Links(categoryID: category.id))
    }

    private func normalized(_ schedule: RecurrenceSchedule) -> RecurrenceSchedule {
        var copy = schedule
        copy.startDate = calendar.calendar.startOfDay(for: schedule.startDate)
        copy.endDate = schedule.endDate.map { calendar.calendar.startOfDay(for: $0) }
        return copy
    }

    private func nextSortOrder() throws -> Int {
        var descriptor = FetchDescriptor<RecurringTransaction>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortOrder ?? -1) + 1
    }
}

enum RecurringReferences {
    /// As the wallet of an income/expense, or either side of a transfer.
    static func isWalletUsed(_ wallet: Wallet, in context: ModelContext) throws -> Bool {
        let id = wallet.id
        let optionalID: UUID? = wallet.id
        return try context.fetchCount(FetchDescriptor<RecurringTransaction>(predicate: #Predicate {
            $0.walletID == id || $0.destinationWalletID == optionalID
        })) > 0
    }

    static func isCategoryUsed(_ category: LedgerCategory, in context: ModelContext) throws -> Bool {
        let optionalID: UUID? = category.id
        return try context.fetchCount(FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.categoryID == optionalID })) > 0
    }
}
