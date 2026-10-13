import Foundation

/// Locale-aware display of `Money`, always using the currency's own precision
/// (VND shows no decimals, KWD shows three).
public struct MoneyFormatter: Sendable {
    public var locale: Locale

    public init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    public func string(from money: Money) -> String {
        money.majorUnits.formatted(
            .currency(code: money.currency.code)
                .precision(.fractionLength(money.currency.minorUnitDigits))
                .locale(locale)
        )
    }
}
