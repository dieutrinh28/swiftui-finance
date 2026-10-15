import Foundation
import SwiftData
import FinanceDomain

/// Version 3: adds savings goals (with contributions) and recurring
/// transactions. Earlier models are reused unchanged.
///
/// Migration from V2 is lightweight (new entities only).
public enum SchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Wallet.self,
            SchemaV1.LedgerCategory.self,
            SchemaV1.LedgerTransaction.self,
            SchemaV1.LedgerEntry.self,
            SchemaV2.Budget.self,
            SavingsGoal.self,
            SavingsContribution.self,
            RecurringTransaction.self,
        ]
    }
}

extension SchemaV3 {
    /// Money set aside for a purpose. An earmark only: contributions never
    /// change wallet balances or net worth.
    @Model
    public final class SavingsGoal {
        public var id: UUID
        public var name: String
        public var targetAmountMinorUnits: Int64
        public var currencyCode: String
        public var targetDate: Date?
        /// Informational: where the money is kept. Not a relationship, so the
        /// goal never affects the wallet.
        public var linkedWalletID: UUID?
        public var note: String?
        public var iconName: String
        public var colorIdentifier: String
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        /// Set when the user marks the goal as done.
        public var completedAt: Date?
        public var archivedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \SavingsContribution.goal)
        public var contributions: [SavingsContribution] = []

        public init(
            id: UUID = UUID(),
            name: String,
            target: Money,
            targetDate: Date? = nil,
            linkedWalletID: UUID? = nil,
            note: String? = nil,
            iconName: String,
            colorIdentifier: String,
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.targetAmountMinorUnits = target.minorUnits
            self.currencyCode = target.currency.code
            self.targetDate = targetDate
            self.linkedWalletID = linkedWalletID
            self.note = note
            self.iconName = iconName
            self.colorIdentifier = colorIdentifier
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.completedAt = nil
            self.archivedAt = nil
        }
    }

    /// A contribution (positive) or withdrawal (negative) for a savings goal.
    @Model
    public final class SavingsContribution {
        public var id: UUID
        /// Signed, in the goal's currency.
        public var amountMinorUnits: Int64
        public var date: Date
        public var dayKey: Int
        public var note: String?
        public var createdAt: Date
        public var goal: SavingsGoal?

        public init(id: UUID = UUID(), amountMinorUnits: Int64, date: Date, dayKey: DayKey, note: String? = nil, createdAt: Date = .now) {
            self.id = id
            self.amountMinorUnits = amountMinorUnits
            self.date = date
            self.dayKey = dayKey.rawValue
            self.note = note
            self.createdAt = createdAt
        }
    }

    /// A scheduled income or expense. Only a definition: occurrences become
    /// transactions when the user records them.
    @Model
    public final class RecurringTransaction {
        public var id: UUID
        public var name: String
        public var kindRaw: String
        /// Unsigned, in the wallet's currency.
        public var amountMinorUnits: Int64
        public var currencyCode: String
        public var walletID: UUID
        public var categoryID: UUID
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
            categoryID: UUID,
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

extension SchemaV3.SavingsGoal {
    public var currency: CurrencyDefinition? { try? CurrencyCatalog.definition(for: currencyCode) }

    public var target: Money? {
        currency.map { Money(minorUnits: targetAmountMinorUnits, currency: $0) }
    }

    public var isArchived: Bool { archivedAt != nil }
    public var isCompleted: Bool { completedAt != nil }

    /// Live contributions, newest first.
    public var contributionsNewestFirst: [SchemaV3.SavingsContribution] {
        contributions.filter { !$0.isDeleted }.sorted { $0.date > $1.date }
    }
}

extension SchemaV3.SavingsContribution {
    public var day: DayKey { DayKey(rawValue: dayKey) }
    public var isWithdrawal: Bool { amountMinorUnits < 0 }
}

extension RecurringTransaction {
    public var kind: TransactionKind? { TransactionKind(rawValue: kindRaw) }
    public var frequency: RecurrenceFrequency? { RecurrenceFrequency(rawValue: frequencyRaw) }

    public var amount: Money? {
        guard let currency = try? CurrencyCatalog.definition(for: currencyCode) else { return nil }
        return Money(minorUnits: amountMinorUnits, currency: currency)
    }

    public var schedule: RecurrenceSchedule? {
        frequency.map { RecurrenceSchedule(frequency: $0, interval: interval, startDate: startDate, endDate: endDate) }
    }

    public var isPaused: Bool { pausedAt != nil }

    public var isTransfer: Bool { kind == .transfer }

    /// Cross-currency transfers: the stored received amount in `destination`'s
    /// currency; nil when none is stored (same currency: equals `amount`).
    public func receivedAmount(in destination: Wallet) throws -> Money? {
        guard let minor = receivedAmountMinorUnits else { return nil }
        return Money(minorUnits: minor, currency: try CurrencyCatalog.definition(for: destination.currencyCode))
    }
}
