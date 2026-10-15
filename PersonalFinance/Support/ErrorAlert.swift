import SwiftUI

/// An error ready to show to the user.
struct AlertError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(_ error: any Error, title: String = String(localized: "Couldn't Save", bundle: .l10n)) {
        self.title = title
        self.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

extension View {
    /// Presents `error` as an alert and clears it when dismissed.
    func errorAlert(_ error: Binding<AlertError?>) -> some View {
        alert(
            error.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}
