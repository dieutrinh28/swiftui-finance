import Foundation
import FinanceDomain

extension Bundle {
    /// This module's texts in the language chosen in the app (see `AppLocalization`).
    static var l10n: Bundle { AppLocalization.bundle(.module) }
}
