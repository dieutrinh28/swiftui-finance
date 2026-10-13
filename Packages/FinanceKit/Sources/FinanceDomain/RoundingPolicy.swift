import Foundation

/// How a value that falls between two minor units is rounded.
/// Every operation that can produce a fraction of a minor unit
/// (conversion, percentages, splitting) must name its policy.
public enum RoundingPolicy: String, Sendable, Codable, CaseIterable {
    /// 0.5 rounds away from zero: 12.345 -> 12.35, -12.345 -> -12.35.
    case halfAwayFromZero
    /// Banker's rounding: 0.5 rounds to the even neighbour: 12.345 -> 12.34.
    case halfEven

    var mode: NSDecimalNumber.RoundingMode {
        switch self {
        case .halfAwayFromZero: .plain
        case .halfEven: .bankers
        }
    }
}

enum DecimalMath {
    static func round(_ value: Decimal, scale: Int, policy: RoundingPolicy) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, policy.mode)
        return output
    }

    /// Converts an integral decimal to Int64, or nil if it is not integral
    /// or does not fit. Goes through the decimal's canonical text form to
    /// avoid the precision loss of NSDecimalNumber.int64Value.
    static func int64(exactly value: Decimal) -> Int64? {
        guard !value.isNaN else { return nil }
        return Int64(value.description)
    }
}
