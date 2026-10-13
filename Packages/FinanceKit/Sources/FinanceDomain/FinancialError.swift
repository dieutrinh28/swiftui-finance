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
            "The currency \(code) is not supported."
        case .currencyMismatch(let expected, let actual):
            "Amounts in \(actual) cannot be combined with amounts in \(expected) without an explicit exchange rate."
        case .arithmeticOverflow:
            "The amount is too large to be recorded."
        case .invalidExchangeRate:
            "The exchange rate must be a positive number between two different currencies."
        case .invalidDateRange:
            "The start date must be before the end date."
        case .nonPositiveAmount:
            "The amount must be greater than zero."
        }
    }
}
