import Foundation
import Observation
import FinanceDomain

/// A language the app can be shown in, or "same as the device".
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case vietnamese = "vi"
    case japanese = "ja"

    var id: String { rawValue }

    /// Shown in its own language, so anyone can find theirs.
    var nativeName: String {
        switch self {
        case .system: String(localized: "Same as device", bundle: .l10n)
        case .english: "English"
        case .vietnamese: "Tiếng Việt"
        case .japanese: "日本語"
        }
    }

    static var languages: [AppLanguage] { allCases.filter { $0 != .system } }
}

/// The language the app is shown in, switchable inside the app.
///
/// One source of truth: the app's own `AppleLanguages` preference, the same
/// value iOS writes from *Settings › Apps › Finance › Language*. So the choice
/// made here and the one made in iOS Settings always agree, and on the next
/// launch the whole app (including system controls and date formats) starts
/// in that language.
///
/// While the app runs, a change applies at once: SwiftUI texts follow
/// `locale` (set on the root view), and `String(localized:bundle: .l10n)`
/// follows `AppLocalization.languageCode`.
@MainActor
@Observable
final class LanguageSettings {
    private(set) var selection: AppLanguage
    /// The language actually shown ("en", "vi" or "ja").
    private(set) var effectiveCode: String

    private static let preferenceKey = "AppleLanguages"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        selection = Self.storedSelection(in: defaults, bundle: bundle)
        effectiveCode = bundle.preferredLocalizations.first.flatMap(Self.supportedCode) ?? AppLanguage.english.rawValue
        AppLocalization.languageCode = effectiveCode
    }

    /// For the root view: the chosen language with the device's region, so
    /// number and currency formats stay as the user set them in iOS.
    var locale: Locale {
        AppLocalization.locale(forLanguage: effectiveCode, region: Locale.current.region)
    }

    var current: AppLanguage { AppLanguage(rawValue: effectiveCode) ?? .english }

    /// Applies `language` now and keeps it for the next launches.
    func select(_ language: AppLanguage) {
        if language == .system {
            defaults.removeObject(forKey: Self.preferenceKey)
        } else {
            defaults.set([language.rawValue], forKey: Self.preferenceKey)
        }
        selection = language
        effectiveCode = language == .system ? Self.deviceLanguageCode(defaults: defaults) : language.rawValue
        AppLocalization.languageCode = effectiveCode
    }

    // MARK: Private

    /// The app's own choice, if any. Without one, `AppleLanguages` comes from
    /// the device (global domain), which means "same as device".
    private static func storedSelection(in defaults: UserDefaults, bundle: Bundle) -> AppLanguage {
        guard let identifier = bundle.bundleIdentifier,
              let own = defaults.persistentDomain(forName: identifier)?[preferenceKey] as? [String],
              let code = own.first.flatMap(supportedCode)
        else { return .system }
        return AppLanguage(rawValue: code) ?? .system
    }

    /// The first of the device's languages the app supports, English otherwise.
    private static func deviceLanguageCode(defaults: UserDefaults) -> String {
        // With the app's own value removed, this reads the device's list.
        let preferred = defaults.stringArray(forKey: preferenceKey) ?? Locale.preferredLanguages
        return preferred.lazy.compactMap(supportedCode).first ?? AppLanguage.english.rawValue
    }

    /// "vi-VN" → "vi"; nil for languages the app doesn't have.
    private static func supportedCode(_ identifier: String) -> String? {
        let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
        return AppLanguage.languages.contains { $0.rawValue == code } ? code : nil
    }
}

extension Bundle {
    /// The app's texts in the language chosen in the app (see `AppLocalization`).
    static var l10n: Bundle { AppLocalization.bundle(.main) }
}
