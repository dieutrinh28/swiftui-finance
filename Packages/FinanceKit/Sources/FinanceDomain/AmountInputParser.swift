import Foundation

public enum AmountInputError: Error, Equatable, Sendable {
    case empty
    case invalidFormat
    case tooManyDecimalPlaces(allowed: Int)
    case tooLarge
}

extension AmountInputError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .empty:
            String(localized: "Please enter an amount.", bundle: .l10n)
        case .invalidFormat:
            String(localized: "The amount isn't a valid number.", bundle: .l10n)
        case .tooManyDecimalPlaces(let allowed):
            allowed == 0
                ? String(localized: "This currency doesn't use decimals.", bundle: .l10n)
                : String(localized: "This currency allows at most \(allowed) decimal places.", bundle: .l10n)
        case .tooLarge:
            String(localized: "The amount is too large.", bundle: .l10n)
        }
    }
}

/// Turns what the user typed into an exact `Money` value, never via `Double`.
///
/// The rules are strict so that input can never be misread:
/// - Currencies without a minor unit (VND, JPY): digits, optionally grouped in
///   threes with "." or "," ("65000", "65.000", "1,250,000"). "65,5" is rejected.
/// - Currencies with a minor unit (USD): digits and at most one decimal mark,
///   either "." or the locale's decimal separator ("12.50", "12,50" in vi_VN).
///   Grouping separators are rejected, so "1,250" can't be misread as 1.25.
/// - Spaces are ignored. Negative numbers are rejected.
public struct AmountInputParser: Sendable {
    public var locale: Locale

    /// Longest accepted integer part. Keeps every value well inside Int64.
    static let maximumIntegerDigits = 15

    public init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    public func parse(_ text: String, currency: CurrencyDefinition) throws -> Money {
        let compact = String(text.filter { !$0.isWhitespace })
        guard !compact.isEmpty else { throw AmountInputError.empty }

        let integerPart: Substring
        let fractionPart: Substring

        if currency.minorUnitDigits == 0 {
            let groups = compact.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
            guard groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(Self.isDigit) }) else {
                throw AmountInputError.invalidFormat
            }
            if groups.count > 1 {
                guard groups[0].count <= 3, groups.dropFirst().allSatisfy({ $0.count == 3 }) else {
                    throw AmountInputError.tooManyDecimalPlaces(allowed: 0)
                }
            }
            integerPart = Substring(groups.joined())
            fractionPart = ""
        } else {
            let localeMark = locale.decimalSeparator?.first ?? "."
            let parts = compact.split(omittingEmptySubsequences: false) { $0 == "." || $0 == localeMark }
            guard parts.count <= 2 else { throw AmountInputError.invalidFormat }
            integerPart = parts[0]
            fractionPart = parts.count == 2 ? parts[1] : ""
            guard !(integerPart.isEmpty && fractionPart.isEmpty),
                  integerPart.allSatisfy(Self.isDigit),
                  fractionPart.allSatisfy(Self.isDigit)
            else { throw AmountInputError.invalidFormat }
            guard fractionPart.count <= currency.minorUnitDigits else {
                throw AmountInputError.tooManyDecimalPlaces(allowed: currency.minorUnitDigits)
            }
        }

        let integerDigits = integerPart.drop { $0 == "0" }
        guard integerDigits.count <= Self.maximumIntegerDigits else { throw AmountInputError.tooLarge }

        let canonical = (integerPart.isEmpty ? "0" : String(integerPart))
            + (fractionPart.isEmpty ? "" : "." + fractionPart)
        guard let value = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")) else {
            throw AmountInputError.invalidFormat
        }
        do {
            return try Money.fromMajorUnits(value, currency: currency)
        } catch {
            throw AmountInputError.tooLarge
        }
    }

    /// Text to pre-fill an amount field when editing: no grouping, the
    /// locale's decimal separator, and exactly the currency's precision.
    /// For example 65000 VND -> "65000", 1250 USD minor units -> "12.50" (or "12,50").
    public func editingText(for money: Money) -> String {
        let digits = money.currency.minorUnitDigits
        let magnitude = money.minorUnits.magnitude
        var scale: UInt64 = 1
        for _ in 0..<digits { scale *= 10 }

        var text = String(magnitude / scale)
        if digits > 0 {
            let fraction = String(magnitude % scale)
            let padded = String(repeating: "0", count: digits - fraction.count) + fraction
            text += (locale.decimalSeparator ?? ".") + padded
        }
        return money.minorUnits < 0 ? "-" + text : text
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
