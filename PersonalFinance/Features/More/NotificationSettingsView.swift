import SwiftUI
import UIKit
import UserNotifications

/// Notification permission, budget alert switch, and an honest description of the limits.
struct NotificationSettingsView: View {
    @Environment(AppContainer.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var status: UNAuthorizationStatus = .notDetermined
    @AppStorage(ReminderCoordinator.budgetAlertsEnabledKey) private var budgetAlertsEnabled = true

    var body: some View {
        List {
            Section {
                LabeledContent("Permission", value: statusText)
                switch status {
                case .notDetermined:
                    Button("Allow Notifications") {
                        Task {
                            await app.reminders.requestAuthorizationIfNeeded()
                            await refresh()
                            await app.refreshNotifications()
                        }
                    }
                case .denied:
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                default:
                    EmptyView()
                }
            } footer: {
                Text("Used for reminders on the day a recurring transaction is due, and for budget alerts.")
            }
            .surfaceRows()

            Section {
                Toggle("Budget alerts", isOn: $budgetAlertsEnabled)
            } footer: {
                Text("A notification when a budget reaches one of its alert levels (set on each budget, 80 percent and used up by default), once per budget period.")
            }
            .surfaceRows()

            Section("How reminders work") {
                Label("iOS decides when notifications are delivered, and Focus or Settings can silence them.", systemImage: "iphone")
                Label("The app never runs in the background and never records a transaction by itself. Due items wait until you open the app and confirm them.", systemImage: "hand.raised")
                Label("Only the next few reminders are scheduled at a time (iOS allows up to 64); the list is refreshed whenever you open the app or change data.", systemImage: "clock.arrow.circlepath")
            }
            .surfaceRows()
            .font(.meta)
        }
        .appGroupedStyle()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: String(localized: "Allowed", bundle: .l10n)
        case .denied: String(localized: "Turned off", bundle: .l10n)
        case .notDetermined: String(localized: "Not asked yet", bundle: .l10n)
        @unknown default: String(localized: "Unknown", bundle: .l10n)
        }
    }

    private func refresh() async {
        status = await app.reminders.authorizationStatus()
    }
}
