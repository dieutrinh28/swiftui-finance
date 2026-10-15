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
    /// Due and upcoming items couldn't be read: said on screen instead of showing none.
    @State private var recurringUnreadable = false
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
                VStack(alignment: .leading, spacing: Spacing.section) {
                    if wallets.isEmpty {
                        WelcomeCard { showingNewWallet = true }
                    } else {
                        // Most needed first: where I stand, what needs me, this period, plans, recent activity.
                        BalanceSummaryCard(state: model?.state) { showingNewTransaction = true }

                        if recurringUnreadable {
                            NoticeBanner(
                                systemImage: "exclamationmark.triangle",
                                title: "Recurring transactions couldn't be checked",
                                message: "Due and upcoming items can't be shown right now.",
                                tone: .attention
                            )
                        } else if dueCount > 0 {
                            NavigationLink(value: AppScreen.due) {
                                NoticeBanner(
                                    systemImage: "bell.badge",
                                    title: "\(dueCount) recurring transaction(s) due",
                                    message: "Review and record them. Nothing is recorded without you.",
                                    tone: .attention,
                                    showsDisclosure: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        if let model {
                            CashFlowSection(model: model)
                        }
                        if !budgets.isEmpty {
                            BudgetsSection(budgets: Array(budgets.prefix(3)), total: budgets.count)
                        }
                        RecentTransactionsSection(transactions: recentTransactions)
                        if let overview = model?.state.value {
                            SpendingByCategorySection(overview: overview)
                        }
                        if !upcoming.isEmpty {
                            UpcomingSection(items: upcoming)
                        }
                        WalletsSection(wallets: wallets)
                        if let overview = model?.state.value {
                            MonthlyTrendSection(overview: overview)
                        }
                    }
                    PrivacyNote()
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.vertical, Spacing.lg)
            }
            .screenBackground()
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
                do {
                    dueCount = try app.recurring.dueOccurrences(at: .now).count
                    upcoming = try app.recurring.upcoming(from: .now, days: 7)
                    recurringUnreadable = false
                } catch {
                    dueCount = 0
                    upcoming = []
                    recurringUnreadable = true
                }
            }
        }
    }
}

/// Reloads after any save and whenever the app becomes active (e.g. the next day).
private struct RefreshKey: Equatable {
    let version: Int
    let phase: ScenePhase
}

/// First run: what the app does, and the one step to start.
private struct WelcomeCard: View {
    let createWallet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Welcome")
                    .font(.heroTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text("A simple, private way to see your money clearly.")
                    .font(.lead)
                    .foregroundStyle(AppColor.textSecondary)
            }

            VStack(alignment: .leading, spacing: Spacing.lg) {
                GoalRow(systemImage: "wallet.pass", tint: PaletteColor.blue.color,
                        title: "Where your money is",
                        detail: "Cash, bank accounts, e-wallets and cards, each with its own balance.")
                GoalRow(systemImage: "arrow.left.arrow.right", tint: PaletteColor.pink.color,
                        title: "Where it goes",
                        detail: "Income and expenses by category, with transfers kept separate.")
                GoalRow(systemImage: "target", tint: PaletteColor.green.color,
                        title: "What it's for",
                        detail: "Budgets and savings goals that track real spending.")
            }

            Button(action: createWallet) {
                Label("Add Your First Wallet", systemImage: "plus")
            }
            .buttonStyle(.appPrimary)
        }
        .cardStyle(padding: Spacing.xl)
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
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(.supporting)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A quiet footer: where the data lives, and where to back it up.
private struct PrivacyNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Stored only on this iPhone", systemImage: "lock.shield")
                .font(.label.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("No account, no server, no tracking. Deleting the app deletes your data, so keep a backup.")
                .font(.meta)
                .foregroundStyle(AppColor.textSecondary)
            NavigationLink(value: AppScreen.backup) {
                Text("Backup & Export")
                    .font(.label.weight(.medium))
                    .foregroundStyle(AppColor.accent)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("New user", traits: .emptyStore) {
    HomeView()
}

#Preview("With data", traits: .sampleData) {
    HomeView()
}
