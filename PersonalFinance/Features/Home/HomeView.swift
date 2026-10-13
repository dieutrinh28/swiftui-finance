import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Home tab: onboarding for a new user, then the dashboard.
///
/// All dashboard figures come from one `DashboardModel.reload()` over a ledger
/// snapshot. The model reloads whenever the main context saves
/// (`AppContainer.dataVersion`) or the period changes.
struct HomeView: View {
    @Environment(AppContainer.self) private var app

    @Query(filter: #Predicate<Wallet> { $0.archivedAt == nil }, sort: \Wallet.sortOrder)
    private var wallets: [Wallet]

    @Query(filter: #Predicate<Budget> { $0.archivedAt == nil }, sort: \Budget.sortOrder)
    private var budgets: [Budget]

    @Query(HomeView.recentDescriptor)
    private var recentTransactions: [LedgerTransaction]

    @State private var model: DashboardModel?
    @State private var dueCount = 0
    @State private var upcoming: [(recurring: RecurringTransaction, occurrence: Occurrence)] = []
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingNewWallet = false
    @State private var showingNewTransaction = false

    nonisolated private static var recentDescriptor: FetchDescriptor<LedgerTransaction> {
        var descriptor = FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 5
        return descriptor
    }

    var body: some View {
        NavigationStack(path: app.router.binding(for: .home)) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if wallets.isEmpty {
                        WelcomeCard { showingNewWallet = true }
                    } else {
                        Button {
                            showingNewTransaction = true
                        } label: {
                            Label("Add Transaction", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        if dueCount > 0 {
                            DueRecurringCard(count: dueCount)
                        }
                        if let model {
                            DashboardSections(model: model)
                        }
                        if !upcoming.isEmpty {
                            UpcomingRecurringCard(items: upcoming)
                        }
                        if !budgets.isEmpty {
                            BudgetsSummaryCard(budgets: Array(budgets.prefix(3)), total: budgets.count)
                        }
                        WalletsSummaryCard(wallets: wallets)
                        RecentTransactionsCard(transactions: recentTransactions)
                    }
                    PrivacyCard()
                }
                .padding(Spacing.lg)
            }
            .background(AppColor.background)
            .navigationTitle("Home")
            .toolbar {
                if !wallets.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingNewTransaction = true
                        } label: {
                            Label("Add Transaction", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewWallet) {
                WalletFormView(mode: .create)
            }
            .sheet(isPresented: $showingNewTransaction) {
                TransactionFormView(mode: .create(wallet: nil))
            }
            .financeDestinations()
            .task(id: RefreshKey(version: app.dataVersion, phase: scenePhase)) {
                guard scenePhase == .active else { return }
                if model == nil {
                    let reports = app.reports
                    model = DashboardModel(policy: app.calendarPolicy) { try reports.snapshot() }
                }
                model?.reload()
                dueCount = (try? app.recurring.dueOccurrences(at: .now).count) ?? 0
                upcoming = (try? app.recurring.upcoming(from: .now, days: 7)) ?? []
            }
        }
    }
}

/// Reloads after any save and whenever the app becomes active (e.g. the next day).
private struct RefreshKey: Equatable {
    let version: Int
    let phase: ScenePhase
}

/// Recurring items waiting for the user to record or skip them.
private struct DueRecurringCard: View {
    let count: Int

    var body: some View {
        NavigationLink(value: AppScreen.due) {
            HStack(spacing: Spacing.md) {
                IconBadge(systemName: "bell.badge", tint: AppColor.liability)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("\(count) recurring transaction(s) due")
                        .font(.headline)
                    Text("Review and record them. Nothing is recorded without you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

/// Recurring items due in the next seven days.
private struct UpcomingRecurringCard: View {
    let items: [(recurring: RecurringTransaction, occurrence: Occurrence)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Coming up this week")
                .font(.headline)
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                NavigationLink(value: item.recurring) {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(item.recurring.name).font(.subheadline.weight(.medium))
                            Text(item.occurrence.date.formatted(.dateTime.weekday(.wide).day().month()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let amount = item.recurring.amount, let kind = item.recurring.kind {
                            MoneyText(money: amount, tone: kind.tone, font: .amountDetail)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }
}

private struct WelcomeCard: View {
    let createWallet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Welcome")
                .font(.title2.bold())
            Text("A simple, private way to see your money clearly.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Spacing.md) {
                GoalRow(systemImage: "wallet.pass", tint: .blue,
                        title: "Where your money is",
                        detail: "Cash, bank accounts, e-wallets and cards, each with its own balance.")
                GoalRow(systemImage: "arrow.left.arrow.right", tint: AppColor.expense,
                        title: "Where it goes",
                        detail: "Income and expenses by category, with transfers kept separate.")
                GoalRow(systemImage: "target", tint: .green,
                        title: "What it's for",
                        detail: "Budgets and savings goals that track real spending.")
            }
            .padding(.vertical, Spacing.sm)

            Button(action: createWallet) {
                Text("Create Your First Wallet")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .cardStyle()
    }
}

private struct GoalRow: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            IconBadge(systemName: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WalletsSummaryCard: View {
    let wallets: [Wallet]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Wallets")
                .font(.headline)
            ForEach(wallets) { wallet in
                NavigationLink(value: wallet) {
                    WalletRow(wallet: wallet)
                }
                .buttonStyle(.plain)
                if wallet.id != wallets.last?.id {
                    Divider()
                }
            }
        }
        .cardStyle()
    }
}

private struct RecentTransactionsCard: View {
    let transactions: [LedgerTransaction]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Recent transactions")
                .font(.headline)
            if transactions.isEmpty {
                Text("Nothing recorded yet. Tap Add Transaction to log your first expense or income.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transactions) { transaction in
                    NavigationLink(value: transaction) {
                        TransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                    if transaction.id != transactions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .cardStyle()
    }
}

private struct PrivacyCard: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Stored only on this iPhone")
                    .font(.subheadline.weight(.semibold))
                Text("No account, no server, no tracking. Deleting the app deletes your data, so keep a backup once export is available in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.accentColor)
        }
        .cardStyle()
    }
}

#Preview("New user", traits: .emptyStore) {
    HomeView()
}

#Preview("With data", traits: .sampleData) {
    HomeView()
}
