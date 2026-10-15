import SwiftUI
import UIKit

extension View {
    /// Every form with text or amount fields: a Done button above the keyboard
    /// (number pads have no return key, and a multi-line note's return adds a
    /// line) and dismissing the keyboard by dragging the form.
    ///
    /// Done ends editing of whichever field has focus, so it works for every
    /// field without each form tracking its focus. Apply it inside the
    /// form's `NavigationStack` (the keyboard toolbar is part of it).
    func keyboardDismissal() -> some View {
        modifier(KeyboardDismissal())
    }
}

private struct KeyboardDismissal: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}
