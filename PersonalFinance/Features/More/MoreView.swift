import SwiftUI
import FinanceFeatures

/// More tab.
struct MoreView: View {
    @Environment(AppContainer.self) private var app
    @AppStorage(BackupFiles.lastBackupKey) private var lastBackupAt: Double = 0

    var body: some View {
        NavigationStack(path: app.router.binding(for: .more)) {
            List {
                Section("Insights") {
                    NavigationLink(value: AppScreen.reports) {
                        Label("Reports", systemImage: "chart.bar.xaxis")
                    }
                }
                Section("Plan") {
                    NavigationLink(value: AppScreen.savingsGoals) {
                        Label("Savings Goals", systemImage: "target")
                    }
                    NavigationLink(value: AppScreen.recurring) {
                        Label("Recurring Transactions", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Section("Organize") {
                    NavigationLink(value: AppScreen.categories) {
                        Label("Categories", systemImage: "square.grid.2x2")
                    }
                }
                Section("Data") {
                    NavigationLink(value: AppScreen.backup) {
                        LabeledContent {
                            Text(lastBackupAt > 0
                                 ? Date(timeIntervalSince1970: lastBackupAt).formatted(.relative(presentation: .named))
                                 : String(localized: "No backup yet"))
                                .foregroundStyle(backupIsStale ? AppColor.liability : Color.secondary)
                        } label: {
                            Label("Backup & Export", systemImage: "externaldrive")
                        }
                    }
                }
                Section("App") {
                    NavigationLink(value: AppScreen.notifications) {
                        Label("Notifications", systemImage: "bell")
                    }
                    NavigationLink(value: AppScreen.dataPrivacy) {
                        Label("Data & Privacy", systemImage: "lock.shield")
                    }
                }
            }
            .navigationTitle("More")
            .financeDestinations()
        }
    }

    private var backupIsStale: Bool {
        lastBackupAt == 0 || Date.now.timeIntervalSince1970 - lastBackupAt > 30 * 86_400
    }
}

#Preview(traits: .emptyStore) {
    MoreView()
}
