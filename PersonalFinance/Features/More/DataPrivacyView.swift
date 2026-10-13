import SwiftUI
import FinancePersistence
import FinanceFeatures

/// Explains where data lives and what the app does not do.
struct DataPrivacyView: View {
    @Environment(AppContainer.self) private var app

    var body: some View {
        List {
            Section {
                Label("Your data is stored only on this iPhone, in the app's private storage.", systemImage: "iphone")
                Label("No account, no login and no internet connection are needed.", systemImage: "wifi.slash")
                Label("No analytics, no tracking and nothing is sent to a server.", systemImage: "hand.raised")
            } header: {
                Text("Where your data lives")
            }

            Section {
                Label("If you delete the app or lose this iPhone without a separate backup, your records are lost.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppColor.liability)
                Text("iCloud sync is not part of this app. Save a backup file regularly and keep it outside this iPhone.")
                    .foregroundStyle(.secondary)
                NavigationLink(value: AppScreen.backup) {
                    Label("Backup & Export", systemImage: "externaldrive")
                }
            } header: {
                Text("Backups")
            }

            Section("Technical") {
                LabeledContent("Storage", value: storageDescription)
                LabeledContent("Database version", value: ModelContainerFactory.currentSchemaVersion)
                LabeledContent("App version", value: appVersion)
            }
        }
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var storageDescription: String {
        switch app.storeLocation {
        case .inMemory: String(localized: "Temporary (in memory)")
        case .file(let url): url.lastPathComponent
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        DataPrivacyView()
    }
    .environment(try! AppContainer(location: .inMemory))
}
