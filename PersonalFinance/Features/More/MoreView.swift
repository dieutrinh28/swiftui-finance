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
                        SettingsLabel("Reports", systemImage: "chart.bar.xaxis", tint: PaletteColor.blue.color)
                    }
                }
                .surfaceRows()
                Section("Plan") {
                    NavigationLink(value: AppScreen.savingsGoals) {
                        SettingsLabel("Savings Goals", systemImage: "target", tint: PaletteColor.green.color)
                    }
                    NavigationLink(value: AppScreen.recurring) {
                        SettingsLabel("Recurring Transactions", systemImage: "arrow.triangle.2.circlepath",
                                      tint: PaletteColor.indigo.color)
                    }
                }
                .surfaceRows()
                Section("Organize") {
                    NavigationLink(value: AppScreen.categories) {
                        SettingsLabel("Categories", systemImage: "square.grid.2x2", tint: PaletteColor.orange.color)
                    }
                }
                .surfaceRows()
                Section("Data") {
                    NavigationLink(value: AppScreen.backup) {
                        LabeledContent {
                            InlineLabel(
                                verbatim: lastBackupAt > 0
                                    ? Date(timeIntervalSince1970: lastBackupAt).formatted(.relative(presentation: .named).locale(.app))
                                    : String(localized: "No backup yet", bundle: .l10n),
                                systemImage: backupIsStale ? "exclamationmark.circle" : nil
                            )
                            .font(.label)
                            .foregroundStyle(backupIsStale ? AppColor.warning : AppColor.textSecondary)
                        } label: {
                            SettingsLabel("Backup & Export", systemImage: "externaldrive", tint: PaletteColor.teal.color)
                        }
                    }
                }
                .surfaceRows()
                Section("App") {
                    NavigationLink(value: AppScreen.language) {
                        LabeledContent {
                            Text(verbatim: app.language.current.nativeName)
                                .foregroundStyle(AppColor.textSecondary)
                        } label: {
                            SettingsLabel("Language", systemImage: "globe", tint: PaletteColor.blue.color)
                        }
                    }
                    NavigationLink(value: AppScreen.notifications) {
                        SettingsLabel("Notifications", systemImage: "bell", tint: PaletteColor.pink.color)
                    }
                    NavigationLink(value: AppScreen.dataPrivacy) {
                        SettingsLabel("Data & Privacy", systemImage: "lock.shield", tint: PaletteColor.gray.color)
                    }
                }
                .surfaceRows()
            }
            .appGroupedStyle()
            .navigationTitle("More")
            .financeDestinations()
        }
    }

    private var backupIsStale: Bool {
        lastBackupAt == 0 || Date.now.timeIntervalSince1970 - lastBackupAt > 30 * 86_400
    }
}

/// A settings row: small tinted icon and a title.
private struct SettingsLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(systemName: systemImage, tint: tint, size: .small)
            Text(title)
                .foregroundStyle(AppColor.textPrimary)
                // Separators start under the title, as in Settings.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }
}

#Preview(traits: .emptyStore) {
    MoreView()
}
