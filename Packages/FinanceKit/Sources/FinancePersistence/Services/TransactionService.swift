import Foundation
import SwiftData
import FinanceDomain

/// Input for recording or editing an income or expense.
public struct CashFlowDraft {
    public var kind: TransactionKind
    /// Unsigned amount in the wallet's currency.
    public var amount: Money
    public var wallet: Wallet
    public var category: LedgerCategory?
    public var date: Date
    public var note: String?
    public var merchant: String?
    /// Set when recording an occurrence of a recurring transaction.
    public var recurringOccurrenceKey: String?
    /// Expenses only. nil: the category's default (`LedgerCategory.isIrregular`).
    public var isIrregular: Bool?

    public init(
        kind: TransactionKind,
        amount: Money,
        wallet: Wallet,
        category: LedgerCategory?,
        date: Date,
        note: String? = nil,
        merchant: String? = nil,
        recurringOccurrenceKey: String? = nil,
        isIrregular: Bool? = nil
    ) {
        self.kind = kind
        self.amount = amount
        self.wallet = wallet
        self.category = category
        self.date = date
        self.note = note
        self.merchant = merchant
        self.recurringOccurrenceKey = recurringOccurrenceKey
        self.isIrregular = isIrregular
    }

    /// What is stored: only expenses can be irregular.
    var resolvedIsIrregular: Bool {
        guard kind == .expense else { return false }
        return isIrregular ?? category?.isIrregular ?? false
    }
}

/// Input for recording or editing a transfer between two of the user's wallets.
public struct TransferDraft {
    public var source: Wallet
    public var destination: Wallet?
    /// Unsigned amount leaving `source`, in its currency.
    public var sent: Money
    /// Unsigned amount arriving in `destination`, in its currency. Required when
    /// the wallets use different currencies; when nil and the currencies match,
    /// it equals `sent`.
    public var received: Money?
    public var date: Date
    public var note: String?
    /// Set when recording an occurrence of a recurring transfer.
    public var recurringOccurrenceKey: String?

    public init(
        source: Wallet,
        destination: Wallet?,
        sent: Money,
        received: Money? = nil,
        date: Date,
        note: String? = nil,
        recurringOccurrenceKey: String? = nil
    ) {
        self.source = source
        self.destination = destination
        self.sent = sent
        self.received = received
        self.date = date
        self.note = note
        self.recurringOccurrenceKey = recurringOccurrenceKey
    }
}

/// Records, edits and deletes income, expenses and transfers.
///
/// Consistency boundary: a transaction header and all its entries (one for
/// income/expense, two for a transfer) are written together and saved once.
/// Validation happens before any model is touched; if the save fails, the
/// context is rolled back, so a transfer can never be half-recorded.
public struct TransactionService {
    private let context: ModelContext
    private let calendar: CalendarPolicy
    private let now: () -> Date

    public init(context: ModelContext, calendar: CalendarPolicy = CalendarPolicy(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    @discardableResult
    public func create(_ draft: CashFlowDraft) throws -> LedgerTransaction {
        let transaction = try insertCashFlow(draft)
        try context.saveOrRollback()
        return transaction
    }

    /// Validates and inserts an income or expense without saving, so a caller
    /// can add related changes and commit everything in one save.
    /// Rejects a recurring occurrence key that is already in the ledger.
    func insertCashFlow(_ draft: CashFlowDraft) throws -> LedgerTransaction {
        let signedAmount = try validate(draft, editing: nil)
        try requireNewOccurrence(draft.recurringOccurrenceKey)

        let transaction = LedgerTransaction(
            kind: draft.kind,
            date: draft.date,
            dayKey: calendar.dayKey(for: draft.date),
            note: TextRules.optionalText(draft.note),
            merchant: TextRules.optionalText(draft.merchant),
            createdAt: now()
        )
        context.insert(transaction)
        transaction.category = draft.category
        transaction.recurringOccurrenceKey = draft.recurringOccurrenceKey
        transaction.isIrregular = draft.resolvedIsIrregular

        let entry = LedgerEntry(amountMinorUnits: signedAmount, currencyCode: draft.wallet.currencyCode)
        context.insert(entry)
        entry.wallet = draft.wallet
        entry.transaction = transaction
        return transaction
    }

    public func update(_ transaction: LedgerTransaction, with draft: CashFlowDraft) throws {
        let entry = try editableEntry(of: transaction)
        let signedAmount = try validate(draft, editing: transaction)
        let note = TextRules.optionalText(draft.note)
        let merchant = TextRules.optionalText(draft.merchant)

        // Saving the form unchanged is not an edit: nothing is written and
        // "Last edited" keeps its date.
        let unchanged = transaction.kindRaw == draft.kind.rawValue
            && transaction.date == draft.date
            && transaction.note == note
            && transaction.merchant == merchant
            && transaction.category?.id == draft.category?.id
            && transaction.isIrregular == draft.resolvedIsIrregular
            && entry.amountMinorUnits == signedAmount
            && entry.wallet?.id == draft.wallet.id
        guard !unchanged else { return }

        transaction.kindRaw = draft.kind.rawValue
        transaction.date = draft.date
        transaction.dayKey = calendar.dayKey(for: draft.date).rawValue
        transaction.note = note
        transaction.merchant = merchant
        transaction.category = draft.category
        transaction.isIrregular = draft.resolvedIsIrregular
        transaction.updatedAt = now()

        entry.amountMinorUnits = signedAmount
        entry.currencyCode = draft.wallet.currencyCode
        entry.wallet = draft.wallet

        try context.saveOrRollback()
    }

    // MARK: Transfers

    /// Records a transfer as one header with two entries: −sent on the source,
    /// +received on the destination. Never income or expense.
    @discardableResult
    public func createTransfer(_ draft: TransferDraft) throws -> LedgerTransaction {
        let transaction = try insertTransfer(draft)
        try context.saveOrRollback()
        return transaction
    }

    /// Validates and inserts a transfer without saving (see `insertCashFlow`).
    func insertTransfer(_ draft: TransferDraft) throws -> LedgerTransaction {
        let legs = try validate(draft)
        try requireNewOccurrence(draft.recurringOccurrenceKey)

        let transaction = LedgerTransaction(
            kind: .transfer,
            date: draft.date,
            dayKey: calendar.dayKey(for: draft.date),
            note: TextRules.optionalText(draft.note),
            createdAt: now()
        )
        context.insert(transaction)
        transaction.exchangeRateText = legs.rateText
        transaction.recurringOccurrenceKey = draft.recurringOccurrenceKey

        let outgoing = LedgerEntry(amountMinorUnits: legs.outgoing, currencyCode: draft.source.currencyCode)
        context.insert(outgoing)
        outgoing.wallet = draft.source
        outgoing.transaction = transaction

        let incoming = LedgerEntry(amountMinorUnits: legs.incoming, currencyCode: legs.destination.currencyCode)
        context.insert(incoming)
        incoming.wallet = legs.destination
        incoming.transaction = transaction
        return transaction
    }

    /// Updates both sides of a transfer together.
    public func updateTransfer(_ transaction: LedgerTransaction, with draft: TransferDraft) throws {
        guard transaction.kind == .transfer else { throw LedgerValidationError.corruptRecord }
        guard transaction.liveEntries.count == 2,
              let outgoing = transaction.transferSource,
              let incoming = transaction.transferDestination
        else { throw LedgerValidationError.corruptRecord }
        guard !(outgoing.wallet?.isArchived ?? true), !(incoming.wallet?.isArchived ?? true) else {
            throw LedgerValidationError.archivedWallet
        }
        let legs = try validate(draft)
        let note = TextRules.optionalText(draft.note)

        // Unchanged: nothing is written (see `update`).
        let unchanged = transaction.date == draft.date
            && transaction.note == note
            && transaction.exchangeRateText == legs.rateText
            && outgoing.amountMinorUnits == legs.outgoing
            && outgoing.wallet?.id == draft.source.id
            && incoming.amountMinorUnits == legs.incoming
            && incoming.wallet?.id == legs.destination.id
        guard !unchanged else { return }

        transaction.date = draft.date
        transaction.dayKey = calendar.dayKey(for: draft.date).rawValue
        transaction.note = note
        transaction.exchangeRateText = legs.rateText
        transaction.updatedAt = now()

        outgoing.amountMinorUnits = legs.outgoing
        outgoing.currencyCode = draft.source.currencyCode
        outgoing.wallet = draft.source

        incoming.amountMinorUnits = legs.incoming
        incoming.currencyCode = legs.destination.currencyCode
        incoming.wallet = legs.destination

        try context.saveOrRollback()
    }

    /// Deletes the transaction and its entries; wallet balances follow automatically.
    /// Deleting a transaction recorded from a recurring item makes that
    /// occurrence due again (its handled key is removed in the same save), so
    /// a mistaken delete can be recorded again.
    public func delete(_ transaction: LedgerTransaction) throws {
        guard !transaction.liveEntries.contains(where: { $0.wallet?.isArchived ?? false }) else {
            throw LedgerValidationError.archivedWallet
        }
        if let key = transaction.recurringOccurrenceKey,
           let recurringID = RecurrenceRules.parseOccurrenceKey(key)?.recurringID {
            var descriptor = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.id == recurringID })
            descriptor.fetchLimit = 1
            if let recurring = try context.fetch(descriptor).first {
                recurring.handledOccurrenceKeys.removeAll { $0 == key }
            }
        }
        context.delete(transaction)
        try context.saveOrRollback()
    }

    // MARK: - Private

    /// Rejects a recurring occurrence key that is already in the ledger.
    private func requireNewOccurrence(_ key: String?) throws {
        guard let key else { return }
        let optionalKey: String? = key
        let existing = try context.fetchCount(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.recurringOccurrenceKey == optionalKey }
        ))
        guard existing == 0 else { throw LedgerValidationError.duplicateOccurrence }
    }

    private struct TransferLegs {
        let destination: Wallet
        let outgoing: Int64
        let incoming: Int64
        let rateText: String?
    }

    private func validate(_ draft: TransferDraft) throws -> TransferLegs {
        guard let destination = draft.destination else {
            throw LedgerValidationError.missingDestinationWallet
        }
        guard let sourceCurrency = draft.source.currency, let destinationCurrency = destination.currency else {
            throw LedgerValidationError.corruptRecord
        }
        let received: Money
        if sourceCurrency == destinationCurrency {
            received = draft.received ?? draft.sent
        } else {
            guard let explicit = draft.received else { throw LedgerValidationError.missingReceivedAmount }
            received = explicit
        }

        try LedgerRules.validateTransfer(TransferCandidate(
            sent: draft.sent,
            received: received,
            sourceCurrency: sourceCurrency,
            destinationCurrency: destinationCurrency,
            isSameWallet: draft.source.id == destination.id,
            sourceIsArchived: draft.source.isArchived,
            destinationIsArchived: destination.isArchived
        ))

        return TransferLegs(
            destination: destination,
            outgoing: try draft.sent.negated().minorUnits,
            incoming: received.minorUnits,
            rateText: LedgerRules.impliedExchangeRate(sent: draft.sent, received: received).map { "\($0)" }
        )
    }

    private func editableEntry(of transaction: LedgerTransaction) throws -> LedgerEntry {
        guard let kind = transaction.kind else { throw LedgerValidationError.corruptRecord }
        guard kind != .transfer else { throw LedgerValidationError.transfersNotSupported }
        let entries = transaction.liveEntries
        guard entries.count == 1, let entry = entries.first else {
            throw LedgerValidationError.corruptRecord
        }
        if entry.wallet?.isArchived ?? false {
            throw LedgerValidationError.archivedWallet
        }
        return entry
    }

    /// Checks every rule and returns the signed amount to store.
    private func validate(_ draft: CashFlowDraft, editing existing: LedgerTransaction?) throws -> Int64 {
        guard let walletCurrency = draft.wallet.currency else {
            throw LedgerValidationError.corruptRecord
        }
        var categoryType: CategoryType?
        if let category = draft.category {
            guard let type = category.type else { throw LedgerValidationError.corruptRecord }
            categoryType = type
        }
        let keepsExisting = existing != nil
            && draft.category != nil
            && existing?.category?.id == draft.category?.id

        try LedgerRules.validateCashFlow(CashFlowCandidate(
            kind: draft.kind,
            amount: draft.amount,
            walletCurrency: walletCurrency,
            walletIsArchived: draft.wallet.isArchived,
            categoryType: categoryType,
            categoryIsArchived: draft.category?.isArchived ?? false,
            keepsExistingCategory: keepsExisting
        ))
        return try LedgerRules.signedMinorUnits(for: draft.kind, amount: draft.amount)
    }
}
