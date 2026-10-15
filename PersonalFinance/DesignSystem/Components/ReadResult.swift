import SwiftUI

/// The one way a screen shows that something could not be read from the store.
///
/// A read that fails must say so (invariant I14): a missing row, a zero or an
/// empty list would look like real data. Use it as a row, as the value of a
/// `LabeledContent`, or inside a section.
struct ReadFailureLabel: View {
    private let text: Text

    init(_ title: LocalizedStringKey = "Couldn't be loaded") {
        text = Text(title)
    }

    /// The error's own message when it has one (it says what is wrong), otherwise `title`.
    init(_ title: LocalizedStringKey, error: any Error) {
        if let message = (error as? LocalizedError)?.errorDescription {
            text = Text(verbatim: message)
        } else {
            text = Text(title)
        }
    }

    var body: some View {
        Label {
            text
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.meta)
        .foregroundStyle(AppColor.negative)
    }
}

/// Shows a value read from the store, or `ReadFailureLabel` when the read throws.
///
///     LabeledContent("Wallet") {
///         ReadResult { try app.recurring.wallet(of: recurring) } content: { Text($0?.name ?? "") }
///     }
///
/// Use it instead of `try?` in a view (convention C8).
struct ReadResult<Value, Content: View>: View {
    private let result: Result<Value, any Error>
    private let failureTitle: LocalizedStringKey
    private let content: (Value) -> Content

    init(failure failureTitle: LocalizedStringKey = "Couldn't be loaded",
         _ read: () throws -> Value,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.result = Result(catching: read)
        self.failureTitle = failureTitle
        self.content = content
    }

    var body: some View {
        switch result {
        case .success(let value):
            content(value)
        case .failure:
            ReadFailureLabel(failureTitle)
        }
    }
}
