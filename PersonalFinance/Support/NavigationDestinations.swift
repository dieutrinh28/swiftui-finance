import SwiftUI
import FinancePersistence
import FinanceFeatures

extension View {
    /// Registers every pushable screen. Apply once at the root of every tab's
    /// `NavigationStack`, then push with `NavigationLink(value:)`:
    /// a record (`Wallet`, `Budget`, …) for its detail screen, or an `AppScreen`.
    func financeDestinations() -> some View {
        navigationDestination(for: Wallet.self) { wallet in
            WalletDetailView(wallet: wallet)
        }
        .navigationDestination(for: LedgerTransaction.self) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .navigationDestination(for: LedgerCategory.self) { category in
            CategoryDetailView(category: category)
        }
        .navigationDestination(for: Budget.self) { budget in
            BudgetDetailView(budget: budget)
        }
        .navigationDestination(for: SavingsGoal.self) { goal in
            SavingsGoalDetailView(goal: goal)
        }
        .navigationDestination(for: RecurringTransaction.self) { recurring in
            RecurringDetailView(recurring: recurring)
        }
        .navigationDestination(for: AppScreen.self) { screen in
            screen.destination
        }
    }
}

extension AppScreen {
    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .due: DueOccurrencesView()
        case .reports: ReportsView()
        case .savingsGoals: SavingsGoalListView()
        case .recurring: RecurringListView()
        case .categories: CategoryListView()
        case .notifications: NotificationSettingsView()
        case .backup: BackupView()
        case .dataPrivacy: DataPrivacyView()
        case .language: LanguageSettingsView()
        }
    }
}

extension AppRouter {
    /// Binding for `NavigationStack(path:)` of `tab`.
    func binding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(get: { self.path(for: tab) }, set: { self.setPath($0, for: tab) })
    }
}
