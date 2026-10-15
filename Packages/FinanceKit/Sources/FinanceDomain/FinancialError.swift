import Foundation

/// Errors raised by financial rules. Every failure is explicit: callers must
/// never paper over these with zero balances or empty results.
public enum FinancialError: Error, Equatable, Sendable {
    case unsupportedCurrency(String)
    case currencyMismatch(expected: String, actual: String)
    case arithmeticOverflow
    case invalidExchangeRate
    case invalidDateRange
    case nonPositiveAmount
}

extension FinancialError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedCurrency(let code):
            String(localized: "The currency \(code) is not supported.", bundle: .l10n)
        case .currencyMismatch(let expected, let actual):
            String(localized: "Amounts in \(actual) cannot be combined with amounts in \(expected) without an explicit exchange rate.", bundle: .l10n)
        case .arithmeticOverflow:
            String(localized: "The amount is too large to be recorded.", bundle: .l10n)
        case .invalidExchangeRate:
            String(localized: "The exchange rate must be a positive number between two different currencies.", bundle: .l10n)
        case .invalidDateRange:
            String(localized: "The start date must be before the end date.", bundle: .l10n)
        case .nonPositiveAmount:
            String(localized: "The amount must be greater than zero.", bundle: .l10n)
        }
    }
}
