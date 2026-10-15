import Foundation
import SwiftData
import FinanceDomain

/// Version 2: adds `Budget`. The ledger models are unchanged and reused from V1.
///
/// Migration from V1 is lightweight (a new entity only); see `FinanceMigrationPlan`.
public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Wallet.self,
            SchemaV1.LedgerCategory.self,
            SchemaV1.LedgerTransaction.self,
            SchemaV1.LedgerEntry.self,
            Budget.self,
        ]
    }
}

extension SchemaV2 {
    /// A spending plan for one or more expense categories. Not a wallet:
    /// it holds no money and never changes balances or transactions.
    ///
    /// Categories and wallet restrictions are stored as id lists rather than
    /// relationships, so budgets never block or cascade ledger changes.
    /// Services keep them consistent (a category or wallet used by a budget
    /// can't be deleted).
    @Model
    public final class Budget {
        public var id: UUID
        public var name: String
        /// Planned amount per period, in `currencyCode` minor units.
        public var plannedAmountMinorUnits: Int64
        public var currencyCode: String
        public var periodRaw: String
        /// First day of the budget (time of day ignored).
        public var startDate: Date
        /// Inclusive last day. Required for custom budgets.
        public var endDate: Date?
        /// Expense categories measured by this budget; children are included.
        public var categoryIDs: [UUID]
        /// Empty means every wallet.
        public var walletIDs: [UUID]
        public var rolloverEnabled: Bool
        /// Percent thresholds for reminders (used from Milestone 5).
        public var alertThresholdPercents: [Int]
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var archivedAt: Date?

        public init(
            id: UUID = UUID(),
            name: String,
            planned: Money,
            period: BudgetPeriod,
            startDate: Date,
            endDate: Date? = nil,
            categoryIDs: [UUID],
            walletIDs: [UUID] = [],
            rolloverEnabled: Bool = false,
            alertThresholdPercents: [Int] = [80, 100],
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.plannedAmountMinorUnits = planned.minorUnits
            self.currencyCode = planned.currency.code
            self.periodRaw = period.rawValue
            self.startDate = startDate
            self.endDate = endDate
            self.categoryIDs = categoryIDs
            self.walletIDs = walletIDs
            self.rolloverEnabled = rolloverEnabled
            self.alertThresholdPercents = alertThresholdPercents
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.archivedAt = nil
        }
    }
}

extension SchemaV2.Budget {
    public var period: BudgetPeriod? { BudgetPeriod(rawValue: periodRaw) }

    public var currency: CurrencyDefinition? {
        try? CurrencyCatalog.definition(for: currencyCode)
    }

    public var plannedAmount: Money? {
        currency.map { Money(minorUnits: plannedAmountMinorUnits, currency: $0) }
    }

    public var schedule: BudgetSchedule? {
        period.map { BudgetSchedule(period: $0, startDate: startDate, endDate: endDate) }
    }

    public var isArchived: Bool { archivedAt != nil }

    public var appliesToAllWallets: Bool { walletIDs.isEmpty }
}
