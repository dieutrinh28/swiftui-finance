import Foundation
import Synchronization

/// The language texts are looked up in when the user picks one inside the app.
///
/// iOS fixes a process's language at launch. To switch without relaunching,
/// the app sets `languageCode`, and every `String(localized:bundle:)` call
/// passes `AppLocalization.bundle(.module)` (or `.main` in the app), which is
/// that language's `.lproj` folder inside the bundle. SwiftUI's own texts
/// follow `environment(\.locale)`.
public enum AppLocalization {
    private static let state = Mutex<String?>(nil)

    /// "en", "vi", "ja", … or nil to use the bundle's launch language.
    public static var languageCode: String? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// The `.lproj` bundle of `languageCode` inside `base`, or `base` itself
    /// when no language is chosen or the bundle has no such localization (a
    /// missing key then falls back to the English key, as usual).
    /// The locale for formatting dates, lists, percentages and amounts: the
    /// chosen language with the device's region (so number formats stay as the
    /// user set them in iOS). Without a choice, the launch locale.
    ///
    /// `Locale.current` keeps the launch language until the app restarts, so
    /// anything formatted in code must use this instead (convention C2).
    public static var locale: Locale {
        guard let code = languageCode else { return .autoupdatingCurrent }
        return locale(forLanguage: code, region: Locale.current.region)
    }

    public static func locale(forLanguage code: String, region: Locale.Region?) -> Locale {
        Locale(languageCode: Locale.LanguageCode(code), languageRegion: region)
    }

    public static func bundle(_ base: Bundle) -> Bundle {
        guard let code = languageCode,
              let path = base.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return base }
        return bundle
    }
}

extension Bundle {
    /// This module's texts in the language chosen in the app.
    static var l10n: Bundle { AppLocalization.bundle(.module) }
}
