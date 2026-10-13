import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }

@MainActor
@Suite("Dashboard and reports models")
struct OverviewModelTests {
    /// Cash 1,000,000 · Bank 5,000,000 · USD 100.00, plus an October lunch, salary and transfer.
    private func makeFixture() throws -> FormFixture {
        let fixture = try FormFixture()
        try fixture.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(65_000), wallet: fixture.cash,
            category: try fixture.category("expense.food"), date: FormFixture.now))
        try fixture.transactions.create(CashFlowDraft(
            kind: .income, amount: vnd(20_000_000), wallet: fixture.bank,
            category: try fixture.category("income.salary"), date: FormFixture.now))
        try fixture.transactions.createTransfer(TransferDraft(
            source: fixture.bank, destination: fixture.cash, sent: vnd(1_000_000), date: FormFixture.now))
        return fixture
    }

    private func dashboard(_ fixture: FormFixture) -> DashboardModel {
        let reports = ReportService(context: fixture.context)
        return DashboardModel(policy: PreviewFixtures.calendarPolicy, now: { FormFixture.now }) {
            try reports.snapshot()
        }
    }

    @Test func dashboardTotalsComeFromTheLedger() throws {
        let fixture = try makeFixture()
        let model = dashboard(fixture)
        #expect(model.state.value == nil)

        model.reload()
        let overview = try #require(model.state.value)

        #expect(overview.primaryCurrency == .vnd)
        #expect(overview.positions.map(\.currency) == [.vnd, .usd])
        // 1,000,000 + 5,000,000 − 65,000 + 20,000,000 (the transfer moves money, it doesn't add any)
        #expect(overview.positions[0].netWorth == vnd(25_935_000))

        let flow = try #require(overview.cashFlow.first { $0.currency == .vnd })
        #expect(flow.income == vnd(20_000_000))
        #expect(flow.expenses == vnd(65_000))

        #expect(overview.topCategories.count == 1)
        #expect(overview.monthlyTrend.count == DashboardModel.trendMonths)
        #expect(overview.monthlyTrend.last?.expenses == vnd(65_000))
        #expect(overview.hasWallets)
    }

    @Test func changingThePeriodChangesCashFlowButNotNetWorth() throws {
        let fixture = try makeFixture()
        let model = dashboard(fixture)

        model.period = .lastMonth
        model.reload()
        let overview = try #require(model.state.value)

        #expect(overview.cashFlow.first?.income == vnd(0))
        #expect(overview.positions[0].netWorth == vnd(25_935_000))
    }

    @Test func dashboardReflectsNewTransactionsOnReload() throws {
        let fixture = try makeFixture()
        let model = dashboard(fixture)
        model.reload()

        try fixture.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(35_000), wallet: fixture.cash,
            category: try fixture.category("expense.food"), date: FormFixture.now))
        model.reload()

        #expect(model.state.value?.cashFlow.first?.expenses == vnd(100_000))
    }

    @Test func loadFailureIsReportedNotHidden() {
        struct Broken: Error {}
        let model = DashboardModel(policy: PreviewFixtures.calendarPolicy) { throw Broken() }
        model.reload()
        #expect(model.state.error is Broken)
        #expect(model.state.value == nil)
    }

    @Test func reportsUseTheSelectedCurrency() throws {
        let fixture = try makeFixture()
        let reports = ReportService(context: fixture.context)
        let model = ReportsModel(policy: PreviewFixtures.calendarPolicy, now: { FormFixture.now }) {
            try reports.snapshot()
        }

        model.reload()
        var report = try #require(model.state.value)
        #expect(report.currency == .vnd)
        #expect(report.availableCurrencies == [.vnd, .usd])
        #expect(report.expensesByCategory.map(\.amount) == [vnd(65_000)])
        #expect(report.expensesByWallet.map(\.key) == [.wallet(fixture.cash.id)])
        #expect(report.monthlyCashFlow.count == ReportsModel.trendMonths)
        #expect(report.netWorthTrend.last?.netWorth == vnd(25_935_000))
        #expect(report.dailyExpenses.count == 31)
        #expect(report.dailyExpenses.last?.cumulative == vnd(65_000))

        model.currency = .usd
        model.reload()
        report = try #require(model.state.value)
        #expect(report.currency == .usd)
        #expect(report.expensesByCategory.isEmpty)
    }
}

@MainActor
@Suite("Transaction list model")
struct TransactionListModelTests {
    private func makeFixture() throws -> (FormFixture, [LedgerTransaction]) {
        let fixture = try FormFixture()
        let calendar = PreviewFixtures.calendarPolicy.calendar
        let september = calendar.date(byAdding: .month, value: -1, to: FormFixture.now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: FormFixture.now)!
        try fixture.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(65_000), wallet: fixture.cash,
            category: try fixture.category("expense.food"), date: FormFixture.now, note: "Phở"))
        try fixture.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(500_000), wallet: fixture.bank,
            category: try fixture.category("expense.shopping"), date: yesterday))
        try fixture.transactions.create(CashFlowDraft(
            kind: .income, amount: vnd(20_000_000), wallet: fixture.bank,
            category: try fixture.category("income.salary"), date: september))
        let all = try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
        return (fixture, all)
    }

    @Test func groupsByDayThenMonth() throws {
        let (_, transactions) = try makeFixture()
        let model = TransactionListModel(policy: PreviewFixtures.calendarPolicy, now: { FormFixture.now })

        let byDay = model.sections(from: transactions)
        #expect(byDay.map(\.id) == [20_261_012, 20_261_011, 20_260_912])

        model.grouping = .month
        let byMonth = model.sections(from: transactions)
        #expect(byMonth.map(\.id) == [202_610, 202_609])
        #expect(byMonth[0].transactions.count == 2)
        #expect(byMonth[0].start.map(PreviewFixtures.calendarPolicy.dayKey) == DayKey(year: 2026, month: 10, day: 1))
    }

    @Test func amountSortIsOneUngroupedList() throws {
        let (_, transactions) = try makeFixture()
        let model = TransactionListModel(policy: PreviewFixtures.calendarPolicy)
        model.query.sort = .largestFirst

        let sections = model.sections(from: transactions)
        #expect(sections.count == 1)
        #expect(sections[0].transactions.first?.displayAmount == vnd(20_000_000))
        #expect(!model.isGroupedByDate)
    }

    @Test func periodFilterAndClear() throws {
        let (_, transactions) = try makeFixture()
        let model = TransactionListModel(policy: PreviewFixtures.calendarPolicy, now: { FormFixture.now })
        model.query.searchText = "pho"
        #expect(model.sections(from: transactions).flatMap(\.transactions).count == 1)

        model.query.searchText = ""
        try model.setPeriod(.thisMonth)
        #expect(model.period == .thisMonth)
        #expect(model.sections(from: transactions).flatMap(\.transactions).count == 2)

        model.query.sort = .oldestFirst
        model.clearFilters()
        #expect(model.period == nil)
        #expect(model.query.sort == .oldestFirst)
        #expect(model.sections(from: transactions).flatMap(\.transactions).count == 3)
    }

    @Test func noResultsGivesNoSections() throws {
        let (_, transactions) = try makeFixture()
        let model = TransactionListModel(policy: PreviewFixtures.calendarPolicy)
        model.query.searchText = "nothing matches this"
        #expect(model.sections(from: transactions).isEmpty)
    }
}
