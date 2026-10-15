import Foundation
import SwiftData
import SwiftUI
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

@MainActor
@Suite("App router")
struct AppRouterTests {
    private func makeBudget(_ fixture: FormFixture) throws -> Budget {
        let model = fixture.budgetModel(.create)
        model.name = "Food"
        model.amountText = "4.000.000"
        model.toggleCategory(try fixture.category("expense.food"))
        #expect(model.save(categories: try fixture.allCategories(), wallets: fixture.allWallets))
        return try #require(try fixture.context.fetch(FetchDescriptor<Budget>()).first)
    }

    @Test func startsOnHomeWithEmptyStacks() {
        let router = AppRouter()
        #expect(router.selectedTab == .home)
        #expect(router.pendingRoute == nil)
        for tab in AppTab.allCases {
            #expect(router.depth(of: tab) == 0)
        }
    }

    @Test func openSwitchesTabAndReplacesItsStack() {
        let router = AppRouter()
        var deep = NavigationPathBuilder.path(AppScreen.reports, AppScreen.categories)
        router.setPath(deep, for: .more)
        #expect(router.depth(of: .more) == 2)

        router.open(AppScreen.recurring, in: .more)
        #expect(router.selectedTab == .more)
        #expect(router.depth(of: .more) == 1)
        #expect(router.depth(of: .home) == 0)          // other tabs untouched

        deep = router.path(for: .more)
        deep.append(AppScreen.due)
        router.setPath(deep, for: .more)
        #expect(router.depth(of: .more) == 2)

        router.popToRoot(.more)
        #expect(router.depth(of: .more) == 0)
        #expect(router.selectedTab == .more)
    }

    @Test func notificationRouteRoundTrips() throws {
        let id = UUID()
        for route in [NotificationRoute.due, .budget(id)] {
            let userInfo: [AnyHashable: Any] = route.userInfo
            #expect(NotificationRoute(userInfo: userInfo) == route)
        }
    }

    @Test func unknownOrMalformedPayloadsAreIgnored() {
        #expect(NotificationRoute(userInfo: [:]) == nil)
        #expect(NotificationRoute(userInfo: ["route": "wallet"]) == nil)
        #expect(NotificationRoute(userInfo: ["route": "budget"]) == nil)
        #expect(NotificationRoute(userInfo: ["route": "budget", "id": "not-a-uuid"]) == nil)
        #expect(NotificationRoute(userInfo: ["route": 42]) == nil)
    }

    @Test func dueReminderOpensDueScreenOnHome() {
        let router = AppRouter()
        router.selectedTab = .wallets
        router.receive(.due)
        #expect(router.pendingRoute == .due)

        #expect(router.resolvePending { _ in nil })
        #expect(router.selectedTab == .home)
        #expect(router.depth(of: .home) == 1)
        #expect(router.pendingRoute == nil)
        #expect(!router.resolvePending { _ in nil })   // consumed once
    }

    @Test func budgetAlertOpensThatBudget() throws {
        let fixture = try FormFixture()
        let budget = try makeBudget(fixture)
        let router = AppRouter()

        router.receive(.budget(budget.id))
        router.resolvePending { try? fixture.budgets.budget(id: $0) }
        #expect(router.selectedTab == .budgets)
        #expect(router.depth(of: .budgets) == 1)
    }

    @Test func deletedBudgetFallsBackToBudgetsTab() throws {
        let fixture = try FormFixture()
        let budget = try makeBudget(fixture)
        let id = budget.id
        try fixture.budgets.delete(budget)
        #expect(try fixture.budgets.budget(id: id) == nil)

        let router = AppRouter()
        router.setPath(NavigationPathBuilder.path(AppScreen.reports), for: .budgets)
        router.receive(.budget(id))
        router.resolvePending { try? fixture.budgets.budget(id: $0) }
        #expect(router.selectedTab == .budgets)
        #expect(router.depth(of: .budgets) == 0)
    }

    /// A budget that can't be read is reported, not silently skipped.
    @Test func unreadableBudgetIsReported() {
        struct ReadError: Error {}
        let router = AppRouter()
        router.receive(.budget(UUID()))
        router.resolvePending { _ in throw ReadError() }
        #expect(router.selectedTab == .budgets)
        #expect(router.depth(of: .budgets) == 0)
        #expect(router.routeFailure is ReadError)

        router.clearRouteFailure()
        #expect(router.routeFailure == nil)
    }
}

/// Small helper to build a `NavigationPath` from screens.
enum NavigationPathBuilder {
    static func path(_ screens: AppScreen...) -> NavigationPath {
        var path = NavigationPath()
        for screen in screens { path.append(screen) }
        return path
    }
}
