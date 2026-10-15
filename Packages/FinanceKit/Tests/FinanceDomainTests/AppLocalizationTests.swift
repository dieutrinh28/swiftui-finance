import Foundation
import Testing
@testable import FinanceDomain

/// Switching the language inside the app (Milestone 7).
@Suite("App localization", .serialized)
struct AppLocalizationTests {
    @Test func withoutAChoiceTheBundleItselfIsUsed() {
        let saved = AppLocalization.languageCode
        defer { AppLocalization.languageCode = saved }

        AppLocalization.languageCode = nil
        #expect(AppLocalization.bundle(.main) === Bundle.main)
    }

    @Test func anUnknownLanguageFallsBackToTheBundle() {
        let saved = AppLocalization.languageCode
        defer { AppLocalization.languageCode = saved }

        AppLocalization.languageCode = "xx"
        #expect(AppLocalization.bundle(.main) === Bundle.main)
        // Messages still read (in the development language) instead of failing.
        #expect(AmountInputError.empty.errorDescription?.isEmpty == false)
    }

    /// Invariant I12: numbers, dates and amounts follow the language picked in the app.
    @Test func formattingFollowsTheChosenLanguage() {
        let saved = AppLocalization.languageCode
        defer { AppLocalization.languageCode = saved }

        AppLocalization.languageCode = "vi"
        #expect(AppLocalization.locale.language.languageCode == "vi")
        #expect(MoneyFormatter().locale.language.languageCode == "vi")

        AppLocalization.languageCode = "ja"
        #expect(AppLocalization.locale.language.languageCode == "ja")
        #expect(MoneyFormatter().locale.language.languageCode == "ja")
    }

    @Test func theRegionIsKeptWhenTheLanguageChanges() {
        let locale = AppLocalization.locale(forLanguage: "en", region: Locale.Region("VN"))
        #expect(locale.language.languageCode == "en")
        #expect(locale.region == Locale.Region("VN"))
    }
}
