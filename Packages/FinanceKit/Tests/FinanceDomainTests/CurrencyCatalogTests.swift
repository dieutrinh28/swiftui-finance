import Testing
@testable import FinanceDomain

@Suite("Currency catalog")
struct CurrencyCatalogTests {
    @Test func onlyVNDIsEnabled() {
        #expect(CurrencyCatalog.enabled == [.vnd])
        #expect(!CurrencyCatalog.isMultiCurrencyEnabled)
        #expect(CurrencyCatalog.enabled.allSatisfy { CurrencyCatalog.supported.contains($0) })
        #expect(CurrencyCatalog.enabled.contains(CurrencyCatalog.defaultCurrency))
    }

    @Test func pickerOptionsKeepAnExistingCurrency() {
        #expect(CurrencyCatalog.pickerOptions(including: nil) == [.vnd])
        #expect(CurrencyCatalog.pickerOptions(including: .vnd) == [.vnd])
        #expect(CurrencyCatalog.pickerOptions(including: .usd) == [.vnd, .usd])

        #expect(!CurrencyCatalog.offersChoice(including: .vnd))
        #expect(CurrencyCatalog.offersChoice(including: .usd))
    }

    @Test func codeShownOnlyWhenItCarriesInformation() {
        #expect(!CurrencyCatalog.showsCode("VND"))
        #expect(!CurrencyCatalog.showsCode("vnd"))
        #expect(CurrencyCatalog.showsCode("USD"))
    }
}
