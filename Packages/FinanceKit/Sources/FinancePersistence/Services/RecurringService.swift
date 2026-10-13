import Foundation
import SwiftData
import FinanceDomain

public struct RecurringDraft {
    public var name: String
    public var kind: TransactionKind
    /// Unsigned, in the wallet's currency.
    public var amount: Money
    public var wallet: Wallet
    public var category: LedgerCategory
    public var schedule: RecurrenceSchedule
    public var note: String?
    public var reminderEnabled: Bool
    public var reminderMinutes: Int

    public init(
        name: String,
        kind: TransactionKind,
        amount: Money,
        wallet: Wallet,
        category: LedgerCategory,
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
        self.schedule = schedule
        self.note = note
        self.reminderEnabled = reminderEnabled
        self.reminderMinutes = reminderMinutes
    }
}

/// An occurrence that is due (on or before today) and not yet recorded or skipped.
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

/// Recurring income and expense definitions and their occurrences.
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
        let name = try validate(draft)
        let recurring = RecurringTransaction(
            name: name,
            kind: draft.kind,
            amount: draft.amount,
            walletID: draft.wallet.id,
            categoryID: draft.category.id,
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
    public func update(_ recurring: RecurringTransaction, with draft: RecurringDraft) throws {
        let name = try validate(draft)
        let schedule = normalized(draft.schedule)
        recurring.name = name
        recurring.kindRaw = draft.kind.rawValue
        recurring.amountMinorUnits = draft.amount.minorUnits
        recurring.currencyCode = draft.amount.currency.code
        recurring.walletID = draft.wallet.id
        recurring.categoryID = draft.category.id
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
        for recurring in definitions where !recurring.isPaused {
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

    /// The next occurrence of each active definition within `days` days, soonest first.
    public func upcoming(from reference: Date, days: Int) throws -> [(recurring: RecurringTransaction, occurrence: Occurrence)] {
        guard let horizon = calendar.calendar.date(byAdding: .day, value: days, to: reference) else { return [] }
        let definitions = try context.fetch(FetchDescriptor<RecurringTransaction>())
        return definitions
            .filter { !$0.isPaused }
            .compactMap { recurring -> (recurring: RecurringTransaction, occurrence: Occurrence)? in
                guard let schedule = recurring.schedule,
                      let next = RecurrenceRules.next(of: schedule, onOrAfter: reference, policy: calendar),
                      next.date <= horizon
                else { return nil }
                return (recurring, next)
            }
            .sorted { $0.occurrence.date < $1.occurrence.date }
    }

    /// Records a due occurrence as a transaction (optionally with a different
    /// amount, e.g. a variable bill) and marks it handled, in one save.
    @discardableResult
    public func record(_ due: DueOccurrence, amount override: Money? = nil) throws -> LedgerTransaction {
        let recurring = due.recurring
        guard !recurring.handledOccurrenceKeys.contains(due.key) else {
            throw LedgerValidationError.duplicateOccurrence
        }
        guard let kind = recurring.kind, let amount = override ?? recurring.amount else {
            throw LedgerValidationError.corruptRecord
        }
        let walletID = recurring.walletID
        let categoryID = recurring.categoryID
        guard let wallet = try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == walletID })).first,
              let category = try context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.id == categoryID })).first
        else { throw LedgerValidationError.corruptRecord }

        do {
            let transaction = try transactions.insertCashFlow(CashFlowDraft(
                kind: kind,
                amount: amount,
                wallet: wallet,
                category: category,
                date: due.occurrence.date,
                note: recurring.note ?? recurring.name,
                recurringOccurrenceKey: due.key
            ))
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

    // MARK: Reminders

    /// Reminders for upcoming occurrences of definitions with reminders on,
    /// soonest first, at most `limit` (iOS keeps at most 64 pending).
    public func plannedReminders(after reference: Date, perDefinition: Int = 3, limit: Int = 60) throws -> [PlannedReminder] {
        let definitions = try context.fetch(FetchDescriptor<RecurringTransaction>())
        var reminders: [PlannedReminder] = []
        for recurring in definitions where recurring.reminderEnabled && !recurring.isPaused {
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

    public func category(of recurring: RecurringTransaction) throws -> LedgerCategory? {
        let id = recurring.categoryID
        return try context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.id == id })).first
    }

    /// Transactions recorded from this definition, newest first.
    public func recordedTransactions(of recurring: RecurringTransaction) throws -> [LedgerTransaction] {
        let prefix = recurring.id.uuidString
        return try context.fetch(FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            .filter { $0.recurringOccurrenceKey?.hasPrefix(prefix) ?? false }
    }

    // MARK: Private

    private func validate(_ draft: RecurringDraft) throws -> String {
        let name = try TextRules.normalizedName(draft.name)
        try RecurrenceRules.validate(draft.schedule, policy: calendar)
        guard let walletCurrency = draft.wallet.currency, let categoryType = draft.category.type else {
            throw LedgerValidationError.corruptRecord
        }
        try LedgerRules.validateCashFlow(CashFlowCandidate(
            kind: draft.kind,
            amount: draft.amount,
            walletCurrency: walletCurrency,
            walletIsArchived: draft.wallet.isArchived,
            categoryType: categoryType,
            categoryIsArchived: draft.category.isArchived
        ))
        guard (0..<(24 * 60)).contains(draft.reminderMinutes) else { throw LedgerValidationError.invalidRecurrence }
        return name
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
    static func isWalletUsed(_ wallet: Wallet, in context: ModelContext) throws -> Bool {
        let id = wallet.id
        return try context.fetchCount(FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.walletID == id })) > 0
    }

    static func isCategoryUsed(_ category: LedgerCategory, in context: ModelContext) throws -> Bool {
        let id = category.id
        return try context.fetchCount(FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.categoryID == id })) > 0
    }
}
