import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Reports: income vs expenses, spending trend, breakdowns by category and
/// wallet, budget vs actual, monthly cash flow and net worth over time.
/// Every figure comes from the persisted ledger via `ReportsModel`.
struct ReportsView: View {
    @Environment(AppContainer.self) private var app
    @State private var model: ReportsModel?

    var body: some View {
        Group {
            if let model {
                ReportsContent(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Reports")
        .task(id: app.dataVersion) {
            if model == nil {
                let reports = app.reports
                model = ReportsModel(policy: app.calendarPolicy) { try reports.snapshot() }
            }
            model?.reload()
        }
    }
}

private struct ReportsContent: View {
    @Bindable var model: ReportsModel

    @Query(filter: #Predicate<Budget> { $0.archivedAt == nil }, sort: \Budget.sortOrder)
    private var budgets: [Budget]

    @Query(filter: #Predicate<SavingsGoal> { $0.archivedAt == nil }, sort: \SavingsGoal.sortOrder)
    private var goals: [SavingsGoal]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                controls

                switch model.state {
                case .idle:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed(let error):
                    Label((error as? LocalizedError)?.errorDescription ?? String(localized: "The report couldn't be calculated."),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppColor.expense)
                        .cardStyle()
                case .loaded(let report):
                    sections(report)
                }
            }
            .padding(Spacing.lg)
        }
        .background(AppColor.background)
        .onChange(of: model.period) { model.reload() }
        .onChange(of: model.currency) { model.reload() }
    }

    private var controls: some View {
        HStack {
            PeriodPicker(selection: $model.period)
            Spacer()
            if let report = model.state.value, report.availableCurrencies.count > 1 {
                Picker("Currency", selection: Binding(
                    get: { model.currency ?? report.currency },
                    set: { model.currency = $0 }
                )) {
                    ForEach(report.availableCurrencies, id: \.self) { currency in
                        Text(currency.code).tag(currency)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private func sections(_ report: ReportOverview) -> some View {
        ReportCard(title: "Income vs expenses") {
            HStack(alignment: .top, spacing: Spacing.lg) {
                StatColumn(title: "Income") { MoneyText(money: report.cashFlow.income, tone: .income, font: .amountDetail) }
                StatColumn(title: "Expenses") { MoneyText(money: report.cashFlow.expenses, tone: .expense, font: .amountDetail) }
                StatColumn(title: "Net") { MoneyText(money: report.cashFlow.net, tone: .balance, font: .amountDetail) }
            }
        }

        ReportCard(title: "Spending trend", subtitle: "Running total of expenses in the period") {
            if report.cashFlow.expenses.isZero {
                EmptyReportText()
            } else {
                MoneyLineChart(
                    points: report.dailyExpenses.map { .init(date: $0.date, value: $0.cumulative) },
                    seriesName: String(localized: "Spent so far"),
                    unit: .day
                )
            }
        }

        ReportCard(title: "Expenses by category") {
            if report.expensesByCategory.isEmpty {
                EmptyReportText()
            } else {
                BreakdownList(rows: report.expensesByCategory.map {
                    BreakdownList.Row.make($0, categories: report.categories)
                })
            }
        }

        ReportCard(title: "Expenses by wallet") {
            if report.expensesByWallet.isEmpty {
                EmptyReportText()
            } else {
                BreakdownList(rows: report.expensesByWallet.map {
                    BreakdownList.Row.make($0, categories: report.categories,
                                           walletNames: report.wallets.mapValues(\.name))
                })
            }
        }

        if !budgets.isEmpty {
            ReportCard(title: "Budget vs actual", subtitle: "Each budget's current period") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(budgets) { budget in
                        NavigationLink(value: budget) {
                            BudgetRow(budget: budget)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        if !goals.isEmpty {
            ReportCard(title: "Savings goals", subtitle: "Money set aside; not counted twice in net worth") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(goals) { goal in
                        NavigationLink(value: goal) {
                            SavingsGoalRow(goal: goal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        ReportCard(title: "Monthly cash flow", subtitle: "Last \(ReportsModel.trendMonths) months") {
            MonthlyCashFlowChart(points: report.monthlyCashFlow, height: 220)
            MonthlyNetTable(points: report.monthlyCashFlow)
        }

        ReportCard(title: "Net worth", subtitle: "Balance of all wallets at the end of each month") {
            MoneyLineChart(
                points: report.netWorthTrend.map { .init(date: $0.start, value: $0.netWorth) },
                seriesName: String(localized: "Net worth")
            )
        }

        Group {
            if report.availableCurrencies.count > 1 {
                Text("Reports use \(report.currency.code) only; other currencies are never converted. Transfers are not income or expenses. Archived wallets are included. Opening balances count from the start.")
            } else {
                Text("Transfers are not income or expenses. Archived wallets are included. Opening balances count from the start.")
            }
        }
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// A titled report card.
private struct ReportCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .cardStyle()
    }
}

private struct EmptyReportText: View {
    var body: some View {
        Text("No expenses in this period.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// The monthly figures as a table: the accessible, exact companion to the chart.
private struct MonthlyNetTable: View {
    let points: [PeriodCashFlow]

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(points.reversed()) { point in
                HStack {
                    Text(point.start.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    MoneyText(money: point.net, tone: .balance, font: .amountDetail)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, Spacing.sm)
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        ReportsView()
            .financeDestinations()
    }
}
