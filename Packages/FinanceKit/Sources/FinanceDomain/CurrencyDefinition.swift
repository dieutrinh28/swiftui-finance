import Foundation

/// An ISO 4217 currency and the precision of its minor unit.
///
/// Precision is always explicit. VND, JPY and KRW have no minor unit,
/// USD and EUR have two digits, KWD has three. Never assume two decimals.
public struct CurrencyDefinition: Hashable, Sendable, CustomStringConvertible {
    /// Upper-case ISO 4217 alphabetic code, for example "VND".
    public let code: String
    /// Digits after the decimal separator in the major unit.
    public let minorUnitDigits: Int

    public init(code: String, minorUnitDigits: Int) {
        precondition((0...4).contains(minorUnitDigits), "Unsupported minor unit precision")
        self.code = code.uppercased()
        self.minorUnitDigits = minorUnitDigits
    }

    public var description: String { code }

    /// 10^minorUnitDigits as an exact decimal.
    public var minorUnitScale: Decimal {
        var result = Decimal(1)
        for _ in 0..<minorUnitDigits { result *= 10 }
        return result
    }
}

extension CurrencyDefinition {
    public static let vnd = CurrencyDefinition(code: "VND", minorUnitDigits: 0)
    public static let usd = CurrencyDefinition(code: "USD", minorUnitDigits: 2)
    public static let eur = CurrencyDefinition(code: "EUR", minorUnitDigits: 2)
    public static let gbp = CurrencyDefinition(code: "GBP", minorUnitDigits: 2)
    public static let jpy = CurrencyDefinition(code: "JPY", minorUnitDigits: 0)
    public static let krw = CurrencyDefinition(code: "KRW", minorUnitDigits: 0)
    public static let cny = CurrencyDefinition(code: "CNY", minorUnitDigits: 2)
    public static let sgd = CurrencyDefinition(code: "SGD", minorUnitDigits: 2)
    public static let thb = CurrencyDefinition(code: "THB", minorUnitDigits: 2)
    public static let aud = CurrencyDefinition(code: "AUD", minorUnitDigits: 2)
    public static let cad = CurrencyDefinition(code: "CAD", minorUnitDigits: 2)
    public static let chf = CurrencyDefinition(code: "CHF", minorUnitDigits: 2)
    public static let hkd = CurrencyDefinition(code: "HKD", minorUnitDigits: 2)
    public static let kwd = CurrencyDefinition(code: "KWD", minorUnitDigits: 3)
}

/// The currencies the app accepts. Persisted currency codes are validated
/// against this list; an unknown code is an error, never a silent default.
public enum CurrencyCatalog {
    public static let supported: [CurrencyDefinition] = [
        .vnd, .usd, .eur, .gbp, .jpy, .krw, .cny, .sgd, .thb, .aud, .cad, .chf, .hkd, .kwd,
    ]

    /// Currency proposed when the user creates their first wallet.
    public static let defaultCurrency: CurrencyDefinition = .vnd

    /// Currencies the UI offers for new wallets, budgets and goals.
    ///
    /// Product decision: VND only for now. The domain and services still
    /// support every currency in `supported` (and tests use USD), so enabling
    /// multi-currency later means adding codes here, nothing else.
    public static let enabled: [CurrencyDefinition] = [.vnd]

    public static var isMultiCurrencyEnabled: Bool { enabled.count > 1 }

    /// What a currency picker should list: the enabled currencies plus
    /// `current`, so a record created in another currency keeps its value.
    public static func pickerOptions(including current: CurrencyDefinition?) -> [CurrencyDefinition] {
        guard let current, !enabled.contains(current) else { return enabled }
        return enabled + [current]
    }

    /// True when the user has a real choice, i.e. a picker is worth showing.
    public static func offersChoice(including current: CurrencyDefinition?) -> Bool {
        pickerOptions(including: current).count > 1
    }

    /// Whether a currency code should be printed next to an amount or a wallet
    /// name. With a single enabled currency, its code is noise.
    public static func showsCode(_ code: String) -> Bool {
        isMultiCurrencyEnabled || code.uppercased() != defaultCurrency.code
    }

    private static let byCode: [String: CurrencyDefinition] =
        Dictionary(uniqueKeysWithValues: supported.map { ($0.code, $0) })

    public static func definition(for code: String) throws -> CurrencyDefinition {
        guard let definition = byCode[code.uppercased()] else {
            throw FinancialError.unsupportedCurrency(code)
        }
        return definition
    }

    public static func isSupported(_ code: String) -> Bool {
        byCode[code.uppercased()] != nil
    }
}
