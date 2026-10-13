import SwiftUI
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Period picker plus the computed dashboard cards.
struct DashboardSections: View {
    @Bindable var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Overview")
                    .font(.title3.bold())
                Spacer()
                PeriodPicker(selection: $model.period)
            }

            switch model.state {
            case .idle:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .cardStyle()
            case .failed(let error):
                Label((error as? LocalizedError)?.errorDescription ?? String(localized: "The overview couldn't be calculated."),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppColor.expense)
                    .cardStyle()
            case .loaded(let overview):
                NetWorthCard(overview: overview)
                CashFlowCard(overview: overview, periodName: model.period.displayName)
                SpendingByCategoryCard(overview: overview)
                MonthlyTrendCard(overview: overview)
            }
        }
        .onChange(of: model.period) {
            model.reload()
        }
    }
}

/// Current balances: assets, liabilities and net worth, one block per currency.
private struct NetWorthCard: View {
    let overview: DashboardOverview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(overview.positions, id: \.currency) { position in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(overview.positions.count > 1 ? "Net worth · \(position.currency.code)" : "Net worth")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MoneyText(money: position.netWorth, tone: .balance, font: .amountHero)
                    HStack(spacing: Spacing.lg) {
                        StatColumn(title: "Assets") {
                            MoneyText(money: position.assets, font: .amountDetail)
                        }
                        StatColumn(title: "Liabilities") {
                            MoneyText(money: position.liabilities, font: .amountDetail)
                        }
                    }
                }
                if position.currency != overview.positions.last?.currency {
                    Divider()
                }
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var footnote: String {
        var text = String(localized: "Current balances of all wallets.")
        if overview.positions.count > 1 {
            text += " " + String(localized: "Amounts in different currencies are never added together.")
        }
        if overview.archivedWalletsWithBalance > 0 {
            text += " " + String(localized: "Includes \(overview.archivedWalletsWithBalance) archived wallet(s) that still hold money.")
        }
        return text
    }
}

/// Income, expenses and net for the selected period.
private struct CashFlowCard: View {
    let overview: DashboardOverview
    let periodName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(periodName)
                .font(.headline)
            ForEach(visibleFlows, id: \.currency) { flow in
                if visibleFlows.count > 1 {
                    Text(flow.currency.code)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: Spacing.lg) {
                    StatColumn(title: "Income") { MoneyText(money: flow.income, tone: .income, font: .amountDetail) }
                    StatColumn(title: "Expenses") { MoneyText(money: flow.expenses, tone: .expense, font: .amountDetail) }
                    StatColumn(title: "Net") { MoneyText(money: flow.net, tone: .balance, font: .amountDetail) }
                }
            }
            Text("Transfers between your own wallets are not counted as income or expenses.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    /// The primary currency always; others only when they had activity.
    private var visibleFlows: [CashFlowSummary] {
        overview.cashFlow.filter {
            $0.currency == overview.primaryCurrency || !$0.income.isZero || !$0.expenses.isZero
        }
    }
}

private struct SpendingByCategoryCard: View {
    let overview: DashboardOverview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Spending by category")
                .font(.headline)
            if overview.topCategories.isEmpty {
                Text("No expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                BreakdownList(rows: overview.topCategories.map {
                    BreakdownList.Row.make($0, categories: overview.categories)
                })
            }
        }
        .cardStyle()
    }
}

private struct MonthlyTrendCard: View {
    let overview: DashboardOverview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Last \(DashboardModel.trendMonths) months")
                .font(.headline)
            MonthlyCashFlowChart(points: overview.monthlyTrend)
        }
        .cardStyle()
    }
}

/// Up to three active budgets with their current progress.
struct BudgetsSummaryCard: View {
    let budgets: [Budget]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Budgets")
                    .font(.headline)
                Spacer()
                if total > budgets.count {
                    Text("\(budgets.count) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(budgets) { budget in
                NavigationLink(value: budget) {
                    BudgetRow(budget: budget)
                }
                .buttonStyle(.plain)
                if budget.id != budgets.last?.id {
                    Divider()
                }
            }
        }
        .cardStyle()
    }
}

/// A small caption over a value.
struct StatColumn<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Dashboard", traits: .sampleData) {
    HomeView()
}
