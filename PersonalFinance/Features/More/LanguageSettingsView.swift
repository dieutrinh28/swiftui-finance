import SwiftUI

/// More › Language: the app's language, switched at once.
struct LanguageSettingsView: View {
    @Environment(AppContainer.self) private var app

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        app.setLanguage(language)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(verbatim: language.nativeName)
                                    .foregroundStyle(AppColor.textPrimary)
                                if language == .system {
                                    Text(verbatim: app.language.current.nativeName)
                                        .font(.meta)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                            }
                            Spacer()
                            if app.language.selection == language {
                                Image(systemName: "checkmark")
                                    .font(.checkmark)
                                    .foregroundStyle(AppColor.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(app.language.selection == language ? .isSelected : [])
                }
            } footer: {
                Text("Changes right away. Built-in categories you haven't renamed switch too; your own names stay as you wrote them. iOS Settings › Apps › Finance › Language changes the same setting.")
            }
            .surfaceRows()
        }
        .appGroupedStyle()
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview(traits: .emptyStore) {
    NavigationStack {
        LanguageSettingsView()
    }
}
