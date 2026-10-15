import Foundation
import FinanceDomain

extension Locale {
    /// The language chosen in the app, with the device's region. Pass it to
    /// every format style used in code (`.formatted(style.locale(.app))`):
    /// `Locale.current` keeps the launch language until the app restarts.
    /// SwiftUI views get the same locale through `environment(\.locale)`.
    static var app: Locale { AppLocalization.locale }
}
