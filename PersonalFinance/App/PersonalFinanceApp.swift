import SwiftUI

@main
struct PersonalFinanceApp: App {
    @State private var launchState: LaunchState
    /// Must be installed before launch finishes so a tap that opens the app is delivered.
    private let notificationResponder = NotificationResponder()

    init() {
        let state = LaunchState.start()
        _launchState = State(initialValue: state)
        notificationResponder.install()
        connectRouter(of: state)
    }

    var body: some Scene {
        WindowGroup {
            switch launchState {
            case .ready(let container):
                RootView()
                    .environment(container)
                    .modelContainer(container.modelContainer)
                    // A language chosen in the app applies at once: SwiftUI
                    // texts follow the locale, and rebuilding the views
                    // re-evaluates every computed text. Tabs and navigation
                    // paths live in `AppRouter`, so the user stays where they are.
                    .environment(\.locale, container.language.locale)
                    // Charts and pickers read days and weeks from the app's
                    // CalendarPolicy (Monday weeks, one time zone), not the device.
                    .environment(\.calendar, container.calendarPolicy.calendar)
                    .id(container.language.effectiveCode)
            case .failed(let failure):
                StoreErrorView(failure: failure) {
                    let state = LaunchState.start()
                    connectRouter(of: state)
                    launchState = state
                }
            }
        }
    }

    private func connectRouter(of state: LaunchState) {
        if case .ready(let container) = state {
            notificationResponder.router = container.router
        }
    }
}
