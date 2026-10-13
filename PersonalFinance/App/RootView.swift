import SwiftUI
import FinanceFeatures

/// The five top-level sections. Each tab owns its own `NavigationStack`, whose
/// path lives in `AppRouter` so navigation can also be driven from outside.
struct RootView: View {
    @Environment(AppContainer.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection: Bindable(app.router).selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle", value: AppTab.transactions) {
                TransactionListView()
            }
            Tab("Budgets", systemImage: "chart.pie", value: AppTab.budgets) {
                BudgetListView()
            }
            Tab("Wallets", systemImage: "wallet.pass", value: AppTab.wallets) {
                WalletListView()
            }
            Tab("More", systemImage: "ellipsis.circle", value: AppTab.more) {
                MoreView()
            }
        }
        // A tapped notification (also one that launched the app) is resolved once the UI is up.
        .onChange(of: app.router.pendingRoute, initial: true) {
            let budgets = app.budgets
            app.router.resolvePending { try? budgets.budget(id: $0) }
        }
        // Reminders and budget alerts follow every saved change and every return to the app.
        .task(id: app.dataVersion) {
            await app.refreshNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await app.refreshNotifications() }
            }
        }
    }
}

#Preview("Sample data", traits: .sampleData) {
    RootView()
}

#Preview("Empty store", traits: .emptyStore) {
    RootView()
}
