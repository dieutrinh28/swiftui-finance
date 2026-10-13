import Foundation
import SwiftData
import FinanceDomain

// Conventions for every model:
// - `id: UUID` is the stable identifier used by backups and cross-references.
//   Uniqueness is enforced by services. `@Attribute(.unique)` / `#Unique` are
//   deliberately not used: on conflict they silently upsert (overwrite).
// - Enums are stored as raw strings (`typeRaw`, `kindRaw`) because enum
//   properties are unreliable inside `#Predicate`. Typed accessors live in
//   extensions below.
// - Relationships are assigned after `context.insert(_:)`, never in `init`.
// - Records referenced by financial history are archived, not deleted.

extension SchemaV1 {
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
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.typeRaw = type.rawValue
            self.iconName = iconName
            self.colorIdentifier = colorIdentifier
            self.seedKey = seedKey
            self.sortOrder = sortOrder
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
}

// MARK: - Typed accessors

extension SchemaV1.Wallet {
    public var type: WalletType {
        get { WalletType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// nil only if the stored code is not in `CurrencyCatalog` (corrupt or newer data).
    public var currency: CurrencyDefinition? {
        try? CurrencyCatalog.definition(for: currencyCode)
    }

    public var openingBalance: Money? {
        currency.map { Money(minorUnits: openingBalanceMinorUnits, currency: $0) }
    }

    public var isArchived: Bool { archivedAt != nil }
}

extension SchemaV1.LedgerCategory {
    /// nil when the stored raw value is unknown. Callers must not guess.
    public var type: CategoryType? { CategoryType(rawValue: typeRaw) }

    public var isArchived: Bool { archivedAt != nil }
}

extension SchemaV1.LedgerTransaction {
    /// nil when the stored raw value is unknown. Callers must not guess.
    public var kind: TransactionKind? { TransactionKind(rawValue: kindRaw) }

    public var day: DayKey { DayKey(rawValue: dayKey) }

    public var exchangeRate: Decimal? {
        exchangeRateText.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }

    /// The unsigned amount to show in lists: the single entry for income and
    /// expense, the outgoing side for a transfer. nil if the record is malformed.
    public var displayAmount: Money? {
        let entry: SchemaV1.LedgerEntry?
        switch kind {
        case .income, .expense: entry = entries.count == 1 ? entries.first : nil
        case .transfer: entry = entries.first { $0.amountMinorUnits < 0 }
        case nil: entry = nil
        }
        guard
            let entry,
            let currency = try? CurrencyCatalog.definition(for: entry.currencyCode),
            let magnitude = Int64(exactly: entry.amountMinorUnits.magnitude)
        else { return nil }
        return Money(minorUnits: magnitude, currency: currency)
    }
}

extension SchemaV1.LedgerEntry {
    public var amount: Money? {
        guard let currency = try? CurrencyCatalog.definition(for: currencyCode) else { return nil }
        return Money(minorUnits: amountMinorUnits, currency: currency)
    }
}
