import SwiftUI
import UIKit

/// Shown when the database cannot be opened. Explains that nothing was
/// deleted, lets the user retry, and exposes details for support.
struct StoreErrorView: View {
    let failure: StoreFailure
    let retry: () -> Void

    @State private var copiedDetails = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColor.expense)
                        .accessibilityHidden(true)

                    Text("Your data couldn't be opened")
                        .font(.title2.bold())

                    Text("Nothing was deleted or reset. Your records stay on this iPhone until the problem is resolved.")
                        .foregroundStyle(.secondary)

                    Text(failure.message)
                        .cardStyle()

                    Button(action: retry) {
                        Text("Try Again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        UIPasteboard.general.string = failure.technicalDetails
                        copiedDetails = true
                    } label: {
                        Label(copiedDetails ? "Details Copied" : "Copy Technical Details",
                              systemImage: copiedDetails ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    DisclosureGroup("Technical details") {
                        Text(failure.technicalDetails)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Spacing.lg)
            }
            .background(AppColor.background)
            .navigationTitle("Database Error")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    StoreErrorView(
        failure: StoreFailure(
            error: CocoaError(.fileReadCorruptFile),
            storeURL: URL(filePath: "/Application Support/PersonalFinance.store")
        ),
        retry: {}
    )
}
