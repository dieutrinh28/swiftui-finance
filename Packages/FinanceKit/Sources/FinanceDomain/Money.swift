import Foundation

/// An exact amount of a single currency, stored in minor units.
///
/// Rules:
/// - Never built from `Double` or `Float`.
/// - Arithmetic and comparison require the same currency and throw otherwise.
/// - Overflow throws instead of trapping or wrapping.
/// - Converting to another currency needs an explicit `ExchangeRate`.
public struct Money: Hashable, Sendable, CustomStringConvertible {
    public let minorUnits: Int64
    public let currency: CurrencyDefinition

    public init(minorUnits: Int64, currency: CurrencyDefinition) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public init(minorUnits: Int64, currencyCode: String) throws {
        self.init(minorUnits: minorUnits, currency: try CurrencyCatalog.definition(for: currencyCode))
    }

    public static func zero(_ currency: CurrencyDefinition) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    /// Builds money from a major-unit decimal such as 12.34 USD or 4000000 VND,
    /// rounding to the currency's precision with the given policy.
    public static func fromMajorUnits(
        _ amount: Decimal,
        currency: CurrencyDefinition,
        rounding: RoundingPolicy = .halfAwayFromZero
    ) throws -> Money {
        let scaled = DecimalMath.round(amount * currency.minorUnitScale, scale: 0, policy: rounding)
        guard let minor = DecimalMath.int64(exactly: scaled) else {
            throw FinancialError.arithmeticOverflow
        }
        return Money(minorUnits: minor, currency: currency)
    }

    /// The exact amount in major units, e.g. 1999 USD minor units -> 19.99.
    public var majorUnits: Decimal {
        Decimal(minorUnits) / currency.minorUnitScale
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isPositive: Bool { minorUnits > 0 }
    public var isNegative: Bool { minorUnits < 0 }

    public var description: String { "\(majorUnits) \(currency.code)" }

    // MARK: Arithmetic

    public func adding(_ other: Money) throws -> Money {
        try requireSameCurrency(as: other)
        let (sum, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { throw FinancialError.arithmeticOverflow }
        return Money(minorUnits: sum, currency: currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        try requireSameCurrency(as: other)
        let (difference, overflow) = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !overflow else { throw FinancialError.arithmeticOverflow }
        return Money(minorUnits: difference, currency: currency)
    }

    public func negated() throws -> Money {
        guard minorUnits != .min else { throw FinancialError.arithmeticOverflow }
        return Money(minorUnits: -minorUnits, currency: currency)
    }

    public func absoluteValue() throws -> Money {
        minorUnits < 0 ? try negated() : self
    }

    /// Sums values that must all be in `currency`. An empty sequence is zero.
    public static func sum(_ values: some Sequence<Money>, currency: CurrencyDefinition) throws -> Money {
        try values.reduce(Money.zero(currency)) { try $0.adding($1) }
    }

    // MARK: Comparison

    public func compare(to other: Money) throws -> ComparisonResult {
        try requireSameCurrency(as: other)
        if minorUnits < other.minorUnits { return .orderedAscending }
        if minorUnits > other.minorUnits { return .orderedDescending }
        return .orderedSame
    }

    /// `self / denominator` as an exact decimal (0.625 for 62.5 %),
    /// or nil when the denominator is zero. Round at the presentation layer.
    public func ratio(to denominator: Money) throws -> Decimal? {
        try requireSameCurrency(as: denominator)
        guard denominator.minorUnits != 0 else { return nil }
        return Decimal(minorUnits) / Decimal(denominator.minorUnits)
    }

    // MARK: Conversion

    /// Converts using an explicit rate. There is no implicit conversion anywhere.
    public func converted(
        using rate: ExchangeRate,
        rounding: RoundingPolicy = .halfAwayFromZero
    ) throws -> Money {
        guard rate.source == currency else {
            throw FinancialError.currencyMismatch(expected: rate.source.code, actual: currency.code)
        }
        return try Money.fromMajorUnits(majorUnits * rate.rate, currency: rate.target, rounding: rounding)
    }

    private func requireSameCurrency(as other: Money) throws {
        guard other.currency == currency else {
            throw FinancialError.currencyMismatch(expected: currency.code, actual: other.currency.code)
        }
    }
}

extension Money: Codable {
    private enum CodingKeys: String, CodingKey {
        case minorUnits
        case currencyCode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let minor = try container.decode(Int64.self, forKey: .minorUnits)
        let code = try container.decode(String.self, forKey: .currencyCode)
        try self.init(minorUnits: minor, currencyCode: code)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minorUnits, forKey: .minorUnits)
        try container.encode(currency.code, forKey: .currencyCode)
    }
}

/// How many units of `target` one unit of `source` buys, in major units.
/// Example: source USD, target VND, rate 25400.
public struct ExchangeRate: Hashable, Sendable {
    public let source: CurrencyDefinition
    public let target: CurrencyDefinition
    public let rate: Decimal

    public init(source: CurrencyDefinition, target: CurrencyDefinition, rate: Decimal) throws {
        guard source != target, !rate.isNaN, rate > 0 else {
            throw FinancialError.invalidExchangeRate
        }
        self.source = source
        self.target = target
        self.rate = rate
    }
}
