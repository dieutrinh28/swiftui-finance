import SwiftUI
import FinanceDomain
import FinancePersistence
import FinanceFeatures

// Dashboard building blocks. All figures come from `DashboardModel` (one
// snapshot of the ledger); these views only lay them out.
//
// Hierarchy: one highlighted summary (net worth + the primary action), then
// plain white sections with their title outside the card, ordered by how
// often people need them.

// MARK: - Summary

/// The single highlighted surface of the dashboard: net worth now, assets and
/// liabilities, and the primary action.
struct BalanceSummaryCard: View {
    let state: LoadState<DashboardOverview>?
    let addTransaction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            switch state {
            case .loaded(let overview)?:
                ForEach(overview.positions, id: \.currency) { position in
                    PositionSummary(
                        position: position,
                        showsCurrency: overview.positions.count > 1
                    )
                }
                if let note = footnote(for: overview) {
                    Text(note)
                        .font(.fine)
                        .foregroundStyle(AppColor.textSecondary)
                }
            case .failed(let error)?:
                Label((error as? LocalizedError)?.errorDescription ?? String(localized: "The overview couldn't be calculated.", bundle: .l10n),
                      systemImage: "exclamationmark.triangle")
                    .font(.supporting)
                    .foregroundStyle(AppColor.negative)
            case .idle?, nil:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 96)
            }

            Button(action: addTransaction) {
                Label("Add Transaction", systemImage: "plus")
            }
            .buttonStyle(.appPrimary)
        }
        .cardStyle(fill: AppColor.softBlue, padding: Spacing.xl, elevated: false)
    }

    private func footnote(for overview: DashboardOverview) -> String? {
        var parts: [String] = []
        if overview.positions.count > 1 {
            parts.append(String(localized: "Amounts in different currencies are never added together.", bundle: .l10n))
        }
        if overview.archivedWalletsWithBalance > 0 {
            parts.append(String(localized: "Includes \(overview.archivedWalletsWithBalance) archived wallet(s) that still hold money.", bundle: .l10n))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

private struct PositionSummary: View {
    let position: CurrencyPosition
    let showsCurrency: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(showsCurrency ? "Net worth · \(position.currency.code)" : "Net worth")
                    .font(.label)
                    .foregroundStyle(AppColor.textSecondary)
                MoneyText(money: position.netWorth, tone: .balance, font: .amountHero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            HStack(alignment: .top, spacing: Spacing.lg) {
                StatColumn(title: "Assets") {
                    MoneyText(money: position.assets, font: .amountDetail)
                }
                StatColumn(title: "Liabilities") {
                    MoneyText(money: position.liabilities, font: .amountDetail)
                }
            }
        }
    }
}

// MARK: - Cash flow

/// Income, expenses and net for the selected period, with the period picker.
struct CashFlowSection: View {
    @Bindable var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Cash flow") {
                PeriodPicker(selection: $model.period)
            }
            switch model.state {
            case .loaded(let overview):
                ForEach(visibleFlows(overview), id: \.currency) { flow in
                    CashFlowSummaryView(flow: flow, showsCurrency: visibleFlows(overview).count > 1)
                }
                Text(overview.cashFlow.contains { !$0.irregularExpenses.isZero }
                     ? "Transfers are not income or expenses. Irregular expenses are not counted as spending; Net includes them."
                     : "Transfers between your own wallets are not counted as income or expenses.")
                    .font(.fine)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, Spacing.xs)
            case .idle:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .cardStyle()
            case .failed:
                EmptyView()  // The summary card above explains the failure.
            }
        }
        .onChange(of: model.period) {
            model.reload()
        }
    }

    /// The primary currency always; others only when they had activity.
    private func visibleFlows(_ overview: DashboardOverview) -> [CashFlowSummary] {
        overview.cashFlow.filter {
            $0.currency == overview.primaryCurrency || !$0.income.isZero || !$0.allExpenses.isZero
        }
    }
}

/// Income and expense tiles with the net below; shared by Home and Reports.
struct CashFlowSummaryView: View {
    let flow: CashFlowSummary
    let showsCurrency: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if showsCurrency {
                Text(flow.currency.code)
                    .font(.fine.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.md) { tiles }
                VStack(spacing: Spacing.md) { tiles }
            }
            if !flow.irregularExpenses.isZero {
                HStack {
                    Label("Irregular expenses", systemImage: "sparkles")
                        .font(.label)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    MoneyText(money: flow.irregularExpenses, tone: .expense, font: .amountDetail)
                }
                .padding(.horizontal, Spacing.xs)
                .accessibilityElement(children: .combine)
            }
            HStack {
                Text("Net")
                    .font(.label)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                MoneyText(money: flow.net, tone: .balance, font: .amountDetail)
            }
            .padding(.horizontal, Spacing.xs)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var tiles: some View {
        SummaryTile(title: "Income", systemImage: "arrow.down.left", fill: AppColor.softGreen, ink: AppColor.positive) {
            MoneyText(money: flow.income, tone: .income, font: .amountLarge)
        }
        SummaryTile(title: "Expenses", systemImage: "arrow.up.right", fill: AppColor.softCoral, ink: AppColor.negative) {
            MoneyText(money: flow.expenses, tone: .expense, font: .amountLarge)
        }
    }
}

/// A compact figure on a soft tint: label + icon, then the amount.
/// The label and the sign of the amount carry the meaning, not the tint.
struct SummaryTile<Value: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let fill: Color
    let ink: Color
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text(title)
                    .foregroundStyle(AppColor.textSecondary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(ink)
            }
            .font(.label.weight(.medium))
            value
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Insights

struct SpendingByCategorySection: View {
    let overview: DashboardOverview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Spending by category")
            Group {
                if overview.topCategories.isEmpty {
                    Text("No expenses in this period.")
                        .font(.supporting)
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    BreakdownList(rows: overview.topCategories.map {
                        BreakdownList.Row.make($0, categories: overview.categories)
                    })
                }
            }
            .cardStyle()
        }
    }
}

struct MonthlyTrendSection: View {
    let overview: DashboardOverview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Last \(DashboardModel.trendMonths) months")
            MonthlyCashFlowChart(points: overview.monthlyTrend)
                .cardStyle()
        }
    }
}

// MARK: - Lists

/// Up to three active budgets with their current progress.
struct BudgetsSection: View {
    let budgets: [Budget]
    let total: Int

    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Budgets") {
                if total > budgets.count {
                    Button("See All (\(total))") { app.router.selectedTab = .budgets }
                }
            }
            VStack(spacing: 0) {
                ForEach(budgets) { budget in
                    NavigationLink(value: budget) {
                        BudgetRow(budget: budget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if budget.id != budgets.last?.id {
                        RowDivider()
                    }
                }
            }
            .cardStyle(padding: Spacing.lg)
        }
    }
}

struct RecentTransactionsSection: View {
    let transactions: [LedgerTransaction]

    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Recent transactions") {
                if !transactions.isEmpty {
                    Button("See All") { app.router.selectedTab = .transactions }
                }
            }
            VStack(spacing: 0) {
                if transactions.isEmpty {
                    Text("Nothing recorded yet. Tap Add Transaction to log your first expense or income.")
                        .font(.supporting)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(transactions) { transaction in
                        NavigationLink(value: transaction) {
                            TransactionRow(transaction: transaction, showsDate: true)
                        }
                        .buttonStyle(.plain)
                        if transaction.id != transactions.last?.id {
                            RowDivider()
                        }
                    }
                }
            }
            .cardStyle(padding: Spacing.lg)
        }
    }
}

struct WalletsSection: View {
    let wallets: [Wallet]

    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Wallets") {
                Button("See All") { app.router.selectedTab = .wallets }
            }
            VStack(spacing: 0) {
                ForEach(wallets) { wallet in
                    NavigationLink(value: wallet) {
                        WalletRow(wallet: wallet)
                            .padding(.vertical, Spacing.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if wallet.id != wallets.last?.id {
                        RowDivider()
                    }
                }
            }
            .cardStyle(padding: Spacing.lg)
        }
    }
}

/// Recurring items due in the next seven days.
struct UpcomingSection: View {
    let items: [(recurring: RecurringTransaction, occurrence: Occurrence)]

    /// Stable identity per occurrence (definition + day), never the array index.
    private struct Item: Identifiable {
        let id: String
        let recurring: RecurringTransaction
        let occurrence: Occurrence
    }

    var body: some View {
        let rows = items.map {
            Item(id: "\($0.recurring.id.uuidString)-\($0.occurrence.day.rawValue)",
                 recurring: $0.recurring, occurrence: $0.occurrence)
        }
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Coming up this week")
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    NavigationLink(value: row.recurring) {
                        HStack(spacing: Spacing.md) {
                            IconBadge(systemName: "calendar", tint: AppColor.accent)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(row.recurring.name)
                                    .font(.rowTitle)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .lineLimit(1)
                                Text(row.occurrence.date.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                                    .font(.meta)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer(minLength: Spacing.sm)
                            if let amount = row.recurring.amount, let kind = row.recurring.kind {
                                MoneyText(money: amount, tone: kind.tone)
                                    .layoutPriority(1)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    if row.id != rows.last?.id {
                        RowDivider()
                    }
                }
            }
            .cardStyle(padding: Spacing.lg)
        }
    }
}

// MARK: - Shared bits

/// A hairline between rows inside a card.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColor.border)
            .frame(height: 1)
            .padding(.vertical, Spacing.sm)
            .accessibilityHidden(true)
    }
}

/// A small label over a value.
struct StatColumn<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.fine)
                .foregroundStyle(AppColor.textSecondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Dashboard", traits: .sampleData) {
    HomeView()
}
