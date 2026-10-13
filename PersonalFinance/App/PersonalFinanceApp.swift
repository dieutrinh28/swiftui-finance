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
