import SwiftUI

/// An icon and a short text on one line, for the value side of `LabeledContent`.
///
/// Don't put a `Label` there: inside a List row (seen on iOS 26), a `Label`
/// used as `LabeledContent`'s content gets its title laid out in a column of
/// almost zero width, so the title wraps one character per line while being
/// measured and the row becomes very tall (or the title disappears when
/// `fixedSize` is applied). A plain `HStack` is laid out normally.
struct InlineLabel: View {
    let title: Text
    let systemImage: String?

    init(_ title: LocalizedStringKey, systemImage: String?) {
        self.title = Text(title)
        self.systemImage = systemImage
    }

    init(verbatim title: String, systemImage: String?) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            title
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        LabeledContent("Category") { InlineLabel(verbatim: "Food & Drinks", systemImage: "fork.knife") }
        LabeledContent("Backup") { InlineLabel("No backup yet", systemImage: "exclamationmark.circle") }
    }
}
