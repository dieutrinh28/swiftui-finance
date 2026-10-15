import Foundation
import SwiftData
import FinanceDomain

/// Version 4 (Milestone 8): spending accuracy.
///
/// - `LedgerTransaction.isIrregular`, `LedgerCategory.isIrregular`:
///   irregular expenses (travel, a laptop, …) still change balances but are
///   left out of spending, budgets and spending reports.
/// - `RecurringTransaction` can be a transfer: `destinationWalletID`,
///   `receivedAmountMinorUnits`, and `categoryID` becomes optional.
///
/// Why the ledger models are copied rather than edited: V1–V3 reuse the V1
/// classes, and a shipped version must never change, or SwiftData no longer
/// recognises stores written with it. The four ledger models are related to
/// each other, so all four get V4 copies; `Budget` and the savings models are
/// unchanged and reused.
///
/// Migration from V3 is lightweight: new attributes have defaults or are
/// optional, and an attribute becoming optional needs no data change.
public enum SchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Wallet.self,
            LedgerCategory.self,
            LedgerTransaction.self,
            LedgerEntry.self,
            SchemaV2.Budget.self,
            SchemaV3.SavingsGoal.self,
            SchemaV3.SavingsContribution.self,
            RecurringTransaction.self,
        ]
    }
}

extension SchemaV4 {
    @Model
    public final class Wallet {
        public var id: UUID
        public var name: String
        public var typeRaw: String
        /// ISO 4217 code. Must not change once the wallet has ledger entries.
        public var currencyCode: String
        /// Balance before the first recorded transaction. Not income.
        /// Negative for a credit card that already carries debt.
        public var openingBalanceMinorUnits: Int64
        public var iconName: String
        public var colorIdentifier: String
        public var note: String?
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var archivedAt: Date?

        /// `.deny`: a wallet with history cannot be deleted, only archived.
        @Relationship(deleteRule: .deny, inverse: \LedgerEntry.wallet)
        public var entries: [LedgerEntry] = []

        public init(
            id: UUID = UUID(),
            name: String,
            type: WalletType,
            currency: CurrencyDefinition,
            openingBalanceMinorUnits: Int64 = 0,
            iconName: String,
            colorIdentifier: String,
            note: String? = nil,
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.typeRaw = type.rawValue
            self.currencyCode = currency.code
            self.openingBalanceMinorUnits = openingBalanceMinorUnits
            self.iconName = iconName
            self.colorIdentifier = colorIdentifier
            self.note = note
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.archivedAt = nil
        }
    }

    @Model
    public final class LedgerCategory {
        public var id: UUID
        public var name: String
        public var typeRaw: String
        public var iconName: String
        public var colorIdentifier: String
        /// Stable key of a built-in category (e.g. "expense.food"); nil for user-created ones.
        public var seedKey: String?
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var archivedAt: Date?
        /// New in V4. Expense categories only: new expenses in this category
        /// start as irregular (the transaction can override it).
        public var isIrregular: Bool = false

        /// Two levels at most: a parent is always top-level (see CategoryRules).
        public var parent: LedgerCategory?

        @Relationship(deleteRule: .nullify, inverse: \LedgerCategory.parent)
        public var children: [LedgerCategory] = []

        /// `.deny`: a category used by history cannot be deleted, only archived or reassigned.
        @Relationship(deleteRule: .deny, inverse: \LedgerTransaction.category)
        public var transactions: [LedgerTransaction] = []

        public init(
            id: UUID = UUID(),
            name: String,
            type: CategoryType,
            iconName: String,
            colorIdentifier: String,
            seedKey: String? = nil,
            sortOrder: Int = 0,
            isIrregular: Bool = false,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.typeRaw = type.rawValue
            self.iconName = iconName
            self.colorIdentifier = colorIdentifier
            self.seedKey = seedKey
            self.sortOrder = sortOrder
            self.isIrregular = isIrregular
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.archivedAt = nil
        }
    }

    @Model
    public final class LedgerTransaction {
        #Index<LedgerTransaction>([\.date], [\.dayKey])

        public var id: UUID
        public var kindRaw: String
        /// The instant the user assigned to the transaction.
        public var date: Date
        /// `DayKey.rawValue` (yyyymmdd) in the user's time zone at entry time.
        public var dayKey: Int
        public var note: String?
        public var merchant: String?
        /// Cross-currency transfers only: target units per source unit,
        /// stored as a POSIX decimal string so it stays exact.
        public var exchangeRateText: String?
        /// Set when generated from a recurring definition; prevents duplicates.
        public var recurringOccurrenceKey: String?
        public var createdAt: Date
        public var updatedAt: Date
        /// New in V4. Expenses only: counts in balances and net worth, but not
        /// in spending, budgets or spending reports.
        public var isIrregular: Bool = false

        public var category: LedgerCategory?

        /// Entries belong to their transaction and are deleted with it.
        @Relationship(deleteRule: .cascade, inverse: \LedgerEntry.transaction)
        public var entries: [LedgerEntry] = []

        public init(
            id: UUID = UUID(),
            kind: TransactionKind,
            date: Date,
            dayKey: DayKey,
            note: String? = nil,
            merchant: String? = nil,
            isIrregular: Bool = false,
            createdAt: Date = .now
        ) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.date = date
            self.dayKey = dayKey.rawValue
            self.note = note
            self.merchant = merchant
            self.exchangeRateText = nil
            self.recurringOccurrenceKey = nil
            self.isIrregular = isIrregular
            self.createdAt = createdAt
            self.updatedAt = createdAt
        }
    }

    @Model
    public final class LedgerEntry {
        public var id: UUID
        /// Signed amount in the wallet currency's minor units.
        /// Positive increases the wallet balance, negative decreases it.
        public var amountMinorUnits: Int64
        /// Always equal to the wallet's currency code.
        public var currencyCode: String

        public var wallet: Wallet?
        public var transaction: LedgerTransaction?

        public init(id: UUID = UUID(), amountMinorUnits: Int64, currencyCode: String) {
            self.id = id
            self.amountMinorUnits = amountMinorUnits
            self.currencyCode = currencyCode
        }
    }

    /// A scheduled income, expense or (new in V4) transfer. Only a definition:
    /// occurrences become transactions when the user records them.
    @Model
    public final class RecurringTransaction {
        public var id: UUID
        public var name: String
        public var kindRaw: String
        /// Unsigned, in the (source) wallet's currency.
        public var amountMinorUnits: Int64
        public var currencyCode: String
        /// The wallet of an income/expense, or the source wallet of a transfer.
        public var walletID: UUID
        /// Income and expenses only; nil for transfers (optional since V4).
        public var categoryID: UUID?
        /// Transfers only (new in V4): the wallet receiving the money.
        public var destinationWalletID: UUID?
        /// Transfers between currencies only (new in V4): unsigned amount
        /// arriving in the destination wallet, in its currency.
        public var receivedAmountMinorUnits: Int64?
        public var frequencyRaw: String
        public var interval: Int
        public var startDate: Date
        public var endDate: Date?
        public var note: String?
        public var reminderEnabled: Bool
        /// Reminder time on the due day, in minutes after midnight (540 = 09:00).
        public var reminderMinutes: Int
        /// Paused definitions produce no due occurrences or reminders.
        public var pausedAt: Date?
        /// Occurrence keys already recorded or skipped.
        public var handledOccurrenceKeys: [String]
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(),
            name: String,
            kind: TransactionKind,
            amount: Money,
            walletID: UUID,
            categoryID: UUID?,
            destinationWalletID: UUID? = nil,
            receivedAmountMinorUnits: Int64? = nil,
            schedule: RecurrenceSchedule,
            note: String? = nil,
            reminderEnabled: Bool = false,
            reminderMinutes: Int = 9 * 60,
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.kindRaw = kind.rawValue
            self.amountMinorUnits = amount.minorUnits
            self.currencyCode = amount.currency.code
            self.walletID = walletID
            self.categoryID = categoryID
            self.destinationWalletID = destinationWalletID
            self.receivedAmountMinorUnits = receivedAmountMinorUnits
            self.frequencyRaw = schedule.frequency.rawValue
            self.interval = schedule.interval
            self.startDate = schedule.startDate
            self.endDate = schedule.endDate
            self.note = note
            self.reminderEnabled = reminderEnabled
            self.reminderMinutes = reminderMinutes
            self.pausedAt = nil
            self.handledOccurrenceKeys = []
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = createdAt
        }
    }
}
