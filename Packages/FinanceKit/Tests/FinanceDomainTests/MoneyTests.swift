import Foundation
import Testing
import FinanceDomain

@Suite("Money")
struct MoneyTests {
    private func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test func addsAndSubtractsSameCurrency() throws {
        let planned = Money(minorUnits: 4_000_000, currency: .vnd)
        let spent = Money(minorUnits: 2_500_000, currency: .vnd)

        #expect(try planned.subtracting(spent) == Money(minorUnits: 1_500_000, currency: .vnd))
        #expect(try spent.adding(spent) == Money(minorUnits: 5_000_000, currency: .vnd))
    }

    @Test func rejectsMixingCurrencies() {
        let vnd = Money(minorUnits: 100_000, currency: .vnd)
        let usd = Money(minorUnits: 500, currency: .usd)

        #expect(throws: FinancialError.currencyMismatch(expected: "VND", actual: "USD")) {
            try vnd.adding(usd)
        }
        #expect(throws: FinancialError.currencyMismatch(expected: "VND", actual: "USD")) {
            try vnd.compare(to: usd)
        }
    }

    @Test func overflowThrowsInsteadOfTrapping() {
        let max = Money(minorUnits: .max, currency: .vnd)
        let one = Money(minorUnits: 1, currency: .vnd)
        let min = Money(minorUnits: .min, currency: .vnd)

        #expect(throws: FinancialError.arithmeticOverflow) { try max.adding(one) }
        #expect(throws: FinancialError.arithmeticOverflow) { try min.subtracting(one) }
        #expect(throws: FinancialError.arithmeticOverflow) { try min.negated() }
    }

    @Test func respectsCurrencyPrecision() throws {
        #expect(try Money.fromMajorUnits(4_000_000, currency: .vnd).minorUnits == 4_000_000)
        #expect(try Money.fromMajorUnits(decimal("19.99"), currency: .usd).minorUnits == 1_999)
        #expect(try Money.fromMajorUnits(decimal("1.234"), currency: .kwd).minorUnits == 1_234)
        #expect(Money(minorUnits: 1_999, currency: .usd).majorUnits == (try decimal("19.99")))
        #expect(Money(minorUnits: 65_000, currency: .vnd).majorUnits == 65_000)
    }

    @Test func roundingPolicyIsExplicit() throws {
        let value = try decimal("12.345")
        #expect(try Money.fromMajorUnits(value, currency: .usd, rounding: .halfAwayFromZero).minorUnits == 1_235)
        #expect(try Money.fromMajorUnits(value, currency: .usd, rounding: .halfEven).minorUnits == 1_234)
        #expect(try Money.fromMajorUnits(decimal("-12.345"), currency: .usd, rounding: .halfAwayFromZero).minorUnits == -1_235)
        #expect(try Money.fromMajorUnits(decimal("12.5"), currency: .vnd, rounding: .halfEven).minorUnits == 12)
    }

    @Test func ratioMatchesBudgetExample() throws {
        let spent = Money(minorUnits: 2_500_000, currency: .vnd)
        let planned = Money(minorUnits: 4_000_000, currency: .vnd)

        #expect(try spent.ratio(to: planned) == (try decimal("0.625")))
        #expect(try spent.ratio(to: .zero(.vnd)) == nil)
    }

    @Test func conversionRequiresExplicitRate() throws {
        let rate = try ExchangeRate(source: .usd, target: .vnd, rate: 25_400)
        let hundredDollars = Money(minorUnits: 10_000, currency: .usd)

        #expect(try hundredDollars.converted(using: rate) == Money(minorUnits: 2_540_000, currency: .vnd))
        #expect(throws: FinancialError.currencyMismatch(expected: "USD", actual: "VND")) {
            try Money(minorUnits: 1, currency: .vnd).converted(using: rate)
        }
    }

    @Test func exchangeRateValidation() {
        #expect(throws: FinancialError.invalidExchangeRate) {
            try ExchangeRate(source: .usd, target: .usd, rate: 1)
        }
        #expect(throws: FinancialError.invalidExchangeRate) {
            try ExchangeRate(source: .usd, target: .vnd, rate: 0)
        }
        #expect(throws: FinancialError.invalidExchangeRate) {
            try ExchangeRate(source: .usd, target: .vnd, rate: -1)
        }
    }

    @Test func sumOfEmptySequenceIsZero() throws {
        #expect(try Money.sum([Money](), currency: .vnd) == .zero(.vnd))
        let values = [65_000, 48_000, 120_000].map { Money(minorUnits: Int64($0), currency: .vnd) }
        #expect(try Money.sum(values, currency: .vnd).minorUnits == 233_000)
    }

    @Test func codableRoundTripUsesCurrencyCode() throws {
        let money = Money(minorUnits: 1_999, currency: .usd)
        let data = try JSONEncoder().encode(money)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"currencyCode\":\"USD\""))
        #expect(try JSONDecoder().decode(Money.self, from: data) == money)
    }

    @Test func decodingUnknownCurrencyFails() {
        let json = Data(#"{"minorUnits":1,"currencyCode":"XYZ"}"#.utf8)
        #expect(throws: FinancialError.unsupportedCurrency("XYZ")) {
            try JSONDecoder().decode(Money.self, from: json)
        }
    }
}

@Suite("Currency catalog and formatting")
struct CurrencyTests {
    @Test func lookupIsCaseInsensitiveAndStrict() throws {
        #expect(try CurrencyCatalog.definition(for: "vnd") == .vnd)
        #expect(throws: FinancialError.unsupportedCurrency("XYZ")) {
            try CurrencyCatalog.definition(for: "XYZ")
        }
    }

    @Test func zeroDecimalCurrencies() {
        #expect(CurrencyDefinition.vnd.minorUnitDigits == 0)
        #expect(CurrencyDefinition.jpy.minorUnitDigits == 0)
        #expect(CurrencyDefinition.usd.minorUnitDigits == 2)
        #expect(CurrencyDefinition.kwd.minorUnitDigits == 3)
    }

    @Test func formatsVNDWithVietnameseConventions() {
        let text = MoneyFormatter(locale: Locale(identifier: "vi_VN"))
            .string(from: Money(minorUnits: 4_000_000, currency: .vnd))

        #expect(text.contains("4.000.000"))
        #expect(text.contains("₫"))
        #expect(!text.contains(","))
    }

    @Test func formatsUSDWithTwoDecimals() {
        let text = MoneyFormatter(locale: Locale(identifier: "en_US"))
            .string(from: Money(minorUnits: 1_999, currency: .usd))
        #expect(text == "$19.99")
    }
}

@Suite("Persisted raw values")
struct RawValueStabilityTests {
    // These strings are stored in the database and in backups.
    // If one of these tests fails, a migration is required.
    @Test func walletTypes() {
        #expect(WalletType.allCases.map(\.rawValue) == [
            "cash", "bankAccount", "eWallet", "savingsAccount", "creditCard", "investmentAccount", "other",
        ])
    }

    @Test func transactionKinds() {
        #expect(TransactionKind.allCases.map(\.rawValue) == ["income", "expense", "transfer"])
        #expect(CategoryType.allCases.map(\.rawValue) == ["income", "expense"])
    }

    @Test func onlyCreditCardIsALiability() {
        let liabilities = WalletType.allCases.filter { $0.accountClass == .liability }
        #expect(liabilities == [.creditCard])
    }

    @Test func transfersAreNotCashFlow() {
        #expect(!TransactionKind.transfer.countsAsCashFlow)
        #expect(TransactionKind.transfer.requiredCategoryType == nil)
        #expect(TransactionKind.expense.requiredCategoryType == .expense)
    }
}
