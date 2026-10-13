import Foundation
import Testing
import FinanceDomain

@Suite("Amount input")
struct AmountInputParserTests {
    private let vietnamese = AmountInputParser(locale: Locale(identifier: "vi_VN"))
    private let american = AmountInputParser(locale: Locale(identifier: "en_US"))

    @Test(arguments: ["65000", "65.000", "65,000", " 65 000 ", "065000"])
    func vndAcceptsGroupedOrPlainDigits(text: String) throws {
        #expect(try vietnamese.parse(text, currency: .vnd).minorUnits == 65_000)
    }

    @Test func vndAcceptsLargeGroupedAmounts() throws {
        #expect(try vietnamese.parse("1.250.000", currency: .vnd).minorUnits == 1_250_000)
        #expect(try american.parse("25,000,000", currency: .vnd).minorUnits == 25_000_000)
    }

    @Test(arguments: ["65,5", "65.00", "1.25.000", ".500"])
    func vndRejectsAnythingThatLooksLikeDecimals(text: String) {
        #expect(throws: (any Error).self) {
            try vietnamese.parse(text, currency: .vnd)
        }
    }

    @Test func usdUsesDotOrLocaleDecimalMark() throws {
        #expect(try american.parse("12.50", currency: .usd).minorUnits == 1_250)
        #expect(try vietnamese.parse("12,50", currency: .usd).minorUnits == 1_250)
        #expect(try vietnamese.parse("12.5", currency: .usd).minorUnits == 1_250)
        #expect(try american.parse(".99", currency: .usd).minorUnits == 99)
        #expect(try american.parse("12", currency: .usd).minorUnits == 1_200)
    }

    @Test func usdRejectsGroupingSoItCannotBeMisread() {
        #expect(throws: AmountInputError.invalidFormat) {
            try american.parse("1,250.00", currency: .usd)
        }
        #expect(throws: AmountInputError.invalidFormat) {
            try american.parse("12,50", currency: .usd)
        }
    }

    @Test func precisionIsEnforced() {
        #expect(throws: AmountInputError.tooManyDecimalPlaces(allowed: 2)) {
            try american.parse("12.345", currency: .usd)
        }
    }

    @Test(arguments: ["", "   ", "-5", "abc", "12a", "1..2", "١٢"])
    func rejectsInvalidInput(text: String) {
        #expect(throws: (any Error).self) {
            try american.parse(text, currency: .usd)
        }
    }

    @Test func rejectsHugeNumbers() {
        #expect(throws: AmountInputError.tooLarge) {
            try american.parse("9999999999999999", currency: .vnd)
        }
    }

    @Test func zeroParsesSoValidationCanReportIt() throws {
        #expect(try american.parse("0", currency: .vnd).isZero)
    }

    @Test func editingTextRoundTrips() throws {
        let usd = Money(minorUnits: 1_205, currency: .usd)
        #expect(american.editingText(for: usd) == "12.05")
        #expect(vietnamese.editingText(for: usd) == "12,05")
        #expect(try vietnamese.parse(vietnamese.editingText(for: usd), currency: .usd) == usd)

        let vnd = Money(minorUnits: 4_000_000, currency: .vnd)
        #expect(vietnamese.editingText(for: vnd) == "4000000")
        #expect(try vietnamese.parse(vietnamese.editingText(for: vnd), currency: .vnd) == vnd)
    }
}
