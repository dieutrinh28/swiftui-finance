import Foundation
import Observation
import SwiftUI
import FinancePersistence

/// The five top-level sections.
public enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home
    case transactions
    case budgets
    case wallets
    case more
}

/// Screens that are not tied to one record. Records themselves (`Wallet`,
/// `Budget`, `LedgerTransaction`, …) are pushed directly as navigation values.
public enum AppScreen: String, Hashable, CaseIterable, Sendable {
    case due
    case reports
    case savingsGoals
    case recurring
    case categories
    case notifications
    case backup
    case dataPrivacy
}

/// Where a tapped notification should lead. Encoded into the notification's
/// `userInfo` when it is scheduled, decoded when the user taps it.
public enum NotificationRoute: Equatable, Sendable {
    /// A recurring reminder: review what is due.
    case due
    /// A budget alert: open that budget.
    case budget(UUID)

    public static let routeKey = "route"
    public static let idKey = "id"

    public var userInfo: [String: String] {
        switch self {
        case .due: [Self.routeKey: "due"]
        case .budget(let id): [Self.routeKey: "budget", Self.idKey: id.uuidString]
        }
    }

    /// nil for notifications this app does not route (or malformed payloads).
    public init?(userInfo: [AnyHashable: Any]) {
        switch userInfo[Self.routeKey] as? String {
        case "due":
            self = .due
        case "budget":
            guard let raw = userInfo[Self.idKey] as? String, let id = UUID(uuidString: raw) else { return nil }
            self = .budget(id)
        default:
            return nil
        }
    }
}

/// App-level navigation state: the selected tab and one navigation path per tab.
///
/// Scope is deliberately small. Screens still push with `NavigationLink(value:)`
/// and own their sheets; the router only exists so that navigation can be
/// driven from outside a screen (a tapped notification today; widgets or
/// shortcuts later).
@MainActor
@Observable
public final class AppRouter {
    public var selectedTab: AppTab = .home

    /// A route received from outside (e.g. a notification tap), waiting until
    /// the UI is ready to resolve it. Lets a cold launch work the same way.
    public private(set) var pendingRoute: NotificationRoute?

    private var paths: [AppTab: NavigationPath] = [:]

    public init() {}

    // MARK: Paths

    public func path(for tab: AppTab) -> NavigationPath {
        paths[tab] ?? NavigationPath()
    }

    public func setPath(_ path: NavigationPath, for tab: AppTab) {
        paths[tab] = path
    }

    /// Number of screens pushed on `tab`'s stack.
    public func depth(of tab: AppTab) -> Int {
        path(for: tab).count
    }

    /// Switches to `tab` and shows `value` directly above its root screen.
    public func open<Value: Hashable>(_ value: Value, in tab: AppTab) {
        var path = NavigationPath()
        path.append(value)
        paths[tab] = path
        selectedTab = tab
    }

    public func popToRoot(_ tab: AppTab) {
        paths[tab] = NavigationPath()
    }

    /// Back to Home with every stack at its root, e.g. after a restore
    /// replaced the records that pushed screens were showing.
    public func reset() {
        paths = [:]
        pendingRoute = nil
        selectedTab = .home
    }

    // MARK: External routes

    public func receive(_ route: NotificationRoute) {
        pendingRoute = route
    }

    /// Navigates to the pending route, if any, and clears it.
    /// A budget that no longer exists falls back to the Budgets tab.
    @discardableResult
    public func resolvePending(budget lookup: (UUID) -> Budget?) -> Bool {
        guard let route = pendingRoute else { return false }
        pendingRoute = nil
        switch route {
        case .due:
            open(AppScreen.due, in: .home)
        case .budget(let id):
            if let budget = lookup(id) {
                open(budget, in: .budgets)
            } else {
                popToRoot(.budgets)
                selectedTab = .budgets
            }
        }
        return true
    }
}
