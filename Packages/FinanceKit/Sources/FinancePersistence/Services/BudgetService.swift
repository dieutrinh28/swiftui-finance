import Foundation
import SwiftData
import FinanceDomain

/// Input for creating or editing a budget.
public struct BudgetDraft {
    public var name: String
    public var plannedAmount: Money
    public var period: BudgetPeriod
    public var startDate: Date
    /// Inclusive last day; required for `.custom`.
    public var endDate: Date?
    /// Expense categories to measure (children are included automatically).
    public var categories: [LedgerCategory]
    /// Wallets to measure; empty means every wallet.
    public var wallets: [Wallet]
    public var rolloverEnabled: Bool

    public init(
        name: String,
        plannedAmount: Money,
        period: BudgetPeriod,
        startDate: Date,
        endDate: Date? = nil,
        categories: [LedgerCategory],
        wallets: [Wallet] = [],
        rolloverEnabled: Bool = false
    ) {
        self.name = name
        self.plannedAmount = plannedAmount
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
        self.categories = categories
        self.wallets = wallets
        self.rolloverEnabled = rolloverEnabled
    }
}

/// Creates and edits budgets and measures them against the ledger.
///
/// A budget never changes transactions or balances; editing a budget only
/// changes how existing transactions are measured.
public struct BudgetService {
    private let context: ModelContext
    private let calendar: CalendarPolicy
    private let now: () -> Date

    public init(context: ModelContext, calendar: CalendarPolicy = CalendarPolicy(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    // MARK: Mutations

    @discardableResult
    public func create(_ draft: BudgetDraft) throws -> Budget {
        let name = try validate(draft)
        let budget = Budget(
            name: name,
            planned: draft.plannedAmount,
            period: draft.period,
            startDate: calendar.calendar.startOfDay(for: draft.startDate),
            endDate: draft.endDate.map { calendar.calendar.startOfDay(for: $0) },
            categoryIDs: uniqueIDs(draft.categories.map(\.id)),
            walletIDs: uniqueIDs(draft.wallets.map(\.id)),
            rolloverEnabled: draft.rolloverEnabled,
            sortOrder: try nextSortOrder(),
            createdAt: now()
        )
        context.insert(budget)
        try context.saveOrRollback()
        return budget
    }

    public func update(_ budget: Budget, with draft: BudgetDraft) throws {
        let name = try validate(draft)
        budget.name = name
        budget.plannedAmountMinorUnits = draft.plannedAmount.minorUnits
        budget.currencyCode = draft.plannedAmount.currency.code
        budget.periodRaw = draft.period.rawValue
        budget.startDate = calendar.calendar.startOfDay(for: draft.startDate)
        budget.endDate = draft.endDate.map { calendar.calendar.startOfDay(for: $0) }
        budget.categoryIDs = uniqueIDs(draft.categories.map(\.id))
        budget.walletIDs = uniqueIDs(draft.wallets.map(\.id))
        budget.rolloverEnabled = draft.rolloverEnabled
        budget.updatedAt = now()
        try context.saveOrRollback()
    }

    public func archive(_ budget: Budget) throws {
        guard !budget.isArchived else { return }
        let timestamp = now()
        budget.archivedAt = timestamp
        budget.updatedAt = timestamp
        try context.saveOrRollback()
    }

    public func restore(_ budget: Budget) throws {
        guard budget.isArchived else { return }
        budget.archivedAt = nil
        budget.updatedAt = now()
        try context.saveOrRollback()
    }

    /// Deleting a budget never touches transactions.
    public func delete(_ budget: Budget) throws {
        context.delete(budget)
        try context.saveOrRollback()
    }

    // MARK: Reads

    /// The budget with `id`, or nil if it was deleted (e.g. an old notification).
    public func budget(id: UUID) throws -> Budget? {
        var descriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func categories(of budget: Budget) throws -> [LedgerCategory] {
        let ids = budget.categoryIDs
        return try context.fetch(FetchDescriptor<LedgerCategory>(
            predicate: #Predicate { ids.contains($0.id) },
            sortBy: [SortDescriptor(\.sortOrder)]
        ))
    }

    public func wallets(of budget: Budget) throws -> [Wallet] {
        let ids = budget.walletIDs
        guard !ids.isEmpty else { return [] }
        return try context.fetch(FetchDescriptor<Wallet>(
            predicate: #Predicate { ids.contains($0.id) },
            sortBy: [SortDescriptor(\.sortOrder)]
        ))
    }

    /// Progress in the period containing `reference`.
    public func progress(for budget: Budget, at reference: Date) throws -> BudgetProgress {
        guard let planned = budget.plannedAmount, let schedule = budget.schedule else {
            throw LedgerValidationError.corruptRecord
        }
        let expenses = BudgetRules.eligibleExpenses(
            try snapshots(for: budget),
            categoryIDs: Set(budget.categoryIDs),
            walletIDs: Set(budget.walletIDs)
        )
        return try BudgetRules.progress(
            planned: planned,
            schedule: schedule,
            rolloverEnabled: budget.rolloverEnabled,
            expenses: expenses,
            reference: reference,
            policy: calendar
        )
    }

    /// The transactions counted in `window`, newest first (all currencies,
    /// so the screen can show which ones were excluded).
    public func spending(for budget: Budget, in window: BudgetWindow) throws -> [LedgerTransaction] {
        let candidates = try candidateTransactions(for: budget)
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return BudgetRules.eligibleSnapshots(
            snapshots(of: candidates),
            categoryIDs: Set(budget.categoryIDs),
            walletIDs: Set(budget.walletIDs)
        )
        .filter { window.contains($0.day) }
        .compactMap { byID[$0.transactionID] }
        .sorted { $0.date > $1.date }
    }

    // MARK: Private

    /// Transactions of the budget's categories and their children.
    private func candidateTransactions(for budget: Budget) throws -> [LedgerTransaction] {
        try categories(of: budget).flatMap { category in
            category.liveTransactions + category.children.flatMap(\.liveTransactions)
        }
    }

    private func snapshots(for budget: Budget) throws -> [ExpenseSnapshot] {
        snapshots(of: try candidateTransactions(for: budget))
    }

    private func snapshots(of transactions: [LedgerTransaction]) -> [ExpenseSnapshot] {
        transactions.compactMap { transaction in
            guard let kind = transaction.kind, let amount = transaction.displayAmount else { return nil }
            return ExpenseSnapshot(
                transactionID: transaction.id,
                kind: kind,
                categoryID: transaction.category?.id,
                parentCategoryID: transaction.category?.parent?.id,
                walletID: transaction.primaryWallet?.id,
                amount: amount,
                day: transaction.day
            )
        }
    }

    private func validate(_ draft: BudgetDraft) throws -> String {
        let name = try TextRules.normalizedName(draft.name)
        guard draft.plannedAmount.isPositive else { throw LedgerValidationError.nonPositiveAmount }
        guard !draft.categories.isEmpty else { throw LedgerValidationError.budgetNeedsCategories }
        for category in draft.categories {
            guard let type = category.type else { throw LedgerValidationError.corruptRecord }
            guard type == .expense else {
                throw LedgerValidationError.categoryTypeMismatch(required: .expense, actual: type)
            }
        }
        for wallet in draft.wallets where wallet.currencyCode != draft.plannedAmount.currency.code {
            throw LedgerValidationError.currencyMismatch(
                walletCurrency: wallet.currencyCode,
                amountCurrency: draft.plannedAmount.currency.code
            )
        }
        try BudgetRules.validateSchedule(
            BudgetSchedule(period: draft.period, startDate: draft.startDate, endDate: draft.endDate),
            policy: calendar
        )
        return name
    }

    private func uniqueIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func nextSortOrder() throws -> Int {
        var descriptor = FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortOrder ?? -1) + 1
    }
}

/// Lookups other services use to keep budget references valid.
enum BudgetReferences {
    static func isCategoryUsed(_ category: LedgerCategory, in context: ModelContext) throws -> Bool {
        try context.fetch(FetchDescriptor<Budget>()).contains { $0.categoryIDs.contains(category.id) }
    }

    static func isWalletUsed(_ wallet: Wallet, in context: ModelContext) throws -> Bool {
        try context.fetch(FetchDescriptor<Budget>()).contains { $0.walletIDs.contains(wallet.id) }
    }
}
