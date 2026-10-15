import Foundation
import Testing
import FinanceDomain

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }
private func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

/// Milestone 8: irregular expenses, sub-category roll-up, alert thresholds.
@Suite("Spending accuracy rules")
struct SpendingAccuracyRulesTests {
    private let october = DayRange(first: day(2026, 10, 1), end: day(2026, 11, 1))
    private let cash = UUID(), food = UUID(), coffee = UUID(), travel = UUID(), salary = UUID()

    /// Income 20,000,000 · Food 300,000 · Coffee (under Food) 45,000 + 55,000 ·
    /// irregular Travel 8,000,000 · an irregular Coffee 200,000 (a coffee machine).
    private var snapshot: LedgerSnapshot {
        func entry(_ kind: TransactionKind, _ minor: Int64, _ category: UUID, irregular: Bool = false) -> EntrySnapshot {
            EntrySnapshot(transactionID: UUID(), kind: kind, day: day(2026, 10, 5), walletID: cash,
                          amount: vnd(minor), categoryID: category, isIrregular: irregular)
        }
        return LedgerSnapshot(
            wallets: [WalletSnapshot(id: cash, name: "Cash", accountClass: .asset, openingBalance: vnd(0))],
            entries: [
                entry(.income, 20_000_000, salary),
                entry(.expense, -300_000, food),
                entry(.expense, -45_000, coffee),
                entry(.expense, -55_000, coffee),
                entry(.expense, -8_000_000, travel, irregular: true),
                entry(.expense, -200_000, coffee, irregular: true),
            ],
            categories: [
                CategorySnapshot(id: food, name: "Food", iconName: "fork.knife", colorIdentifier: "orange"),
                CategorySnapshot(id: coffee, name: "Coffee", iconName: "cup.and.saucer", colorIdentifier: "brown",
                                 parentID: food),
                CategorySnapshot(id: travel, name: "Travel", iconName: "airplane", colorIdentifier: "teal"),
                CategorySnapshot(id: salary, name: "Salary", iconName: "banknote", colorIdentifier: "green"),
            ]
        )
    }

    @Test func cashFlowSeparatesIrregularExpensesButNetIncludesThem() throws {
        let flow = try ReportRules.cashFlow(snapshot, in: october, currency: .vnd)
        #expect(flow.income == vnd(20_000_000))
        #expect(flow.expenses == vnd(400_000))                 // spending: regular only
        #expect(flow.irregularExpenses == vnd(8_200_000))
        #expect(flow.allExpenses == vnd(8_600_000))
        #expect(flow.net == vnd(11_400_000))                   // matches the change in balance
        let balance = try #require(try ReportRules.balances(snapshot)[cash])
        #expect(balance == flow.net)
    }

    @Test func categoryBreakdownRollsSubcategoriesIntoTheirParent() throws {
        let shares = try ReportRules.expensesByCategory(snapshot, in: october, currency: .vnd)
        #expect(shares.map(\.key) == [.category(food)])        // Travel is irregular only
        #expect(shares.first?.amount == vnd(400_000))

        let within = try ReportRules.expensesWithin(food, snapshot, in: october, currency: .vnd)
        #expect(within.map(\.key) == [.category(food), .category(coffee)])
        #expect(within.map(\.amount) == [vnd(300_000), vnd(100_000)])

        #expect(ReportRules.categoriesWithSubcategorySpending(snapshot, in: october, currency: .vnd) == [food])
    }

    @Test func irregularBreakdownAlsoRollsUp() throws {
        let shares = try ReportRules.irregularExpensesByCategory(snapshot, in: october, currency: .vnd)
        #expect(shares.map(\.key) == [.category(travel), .category(food)])
        #expect(shares.map(\.amount) == [vnd(8_000_000), vnd(200_000)])
    }

    @Test func filteringByAParentAlsoFindsItsSubcategories() {
        func item(_ category: UUID, parent: UUID? = nil) -> TransactionSummary {
            TransactionSummary(id: UUID(), kind: .expense, date: .now, day: day(2026, 10, 5), amount: vnd(1),
                               walletIDs: [cash], categoryID: category, parentCategoryID: parent, searchableText: "")
        }
        let lunch = item(food), latte = item(coffee, parent: food), flight = item(travel)
        var query = TransactionQuery()
        query.categoryIDs = [food]
        let found: Set<UUID> = Set(query.apply(to: [lunch, latte, flight]).map(\.id))
        #expect(found == [lunch.id, latte.id])
        query.categoryIDs = [coffee]
        #expect(query.apply(to: [lunch, latte, flight]).map(\.id) == [latte.id])
    }

    @Test func alertThresholdsAreASubsetOfTheAllowedLevels() throws {
        #expect(try BudgetAlertRules.normalizedThresholds([100, 50, 100]) == [50, 100])
        #expect(try BudgetAlertRules.normalizedThresholds([]) == [])
        #expect(throws: LedgerValidationError.invalidAlertThresholds) {
            try BudgetAlertRules.normalizedThresholds([75])
        }
    }
}
