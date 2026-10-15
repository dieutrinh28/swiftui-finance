import Foundation

/// Where a savings goal stands.
public struct SavingsProgress: Sendable, Equatable {
    public let target: Money
    /// Contributions minus withdrawals.
    public let saved: Money
    /// What is still needed; never negative.
    public let remaining: Money
    /// saved ÷ target, between 0 and 1.
    public let fraction: Decimal
    public let isReached: Bool
    /// Calendar months left including the current one; nil without a target date, 0 when it has passed.
    public let monthsLeft: Int?
    /// remaining ÷ monthsLeft, rounded up so the goal is reached in time.
    /// nil without a target date, when reached, or when the date has passed.
    public let suggestedMonthly: Money?
    /// The target date has passed and the goal is not reached.
    public let isOverdue: Bool
}

/// Savings goal rules.
///
/// A goal is an **earmark**: contributions and withdrawals record how much of
/// your money is set aside for the goal. They never move money between
/// wallets and never change balances or net worth, so nothing is counted twice.
/// To actually move money into a savings account, record a transfer as well.
public enum SavingsRules {
    public static func progress(
        target: Money,
        entries: [Money],
        targetDate: Date?,
        reference: Date,
        policy: CalendarPolicy
    ) throws -> SavingsProgress {
        guard target.isPositive else { throw LedgerValidationError.nonPositiveAmount }
        let saved = try Money.sum(entries, currency: target.currency)
        let difference = try target.subtracting(saved)
        let remaining = difference.isPositive ? difference : .zero(target.currency)
        let ratio = try saved.ratio(to: target) ?? 0
        let fraction = min(max(ratio, 0), 1)
        let isReached = !remaining.isPositive

        var monthsLeft: Int?
        var isOverdue = false
        if let targetDate {
            let calendar = policy.calendar
            if policy.dayKey(for: targetDate) < policy.dayKey(for: reference) {
                monthsLeft = 0
                isOverdue = !isReached
            } else if let thisMonth = calendar.dateInterval(of: .month, for: reference)?.start,
                      let targetMonth = calendar.dateInterval(of: .month, for: targetDate)?.start {
                monthsLeft = (calendar.dateComponents([.month], from: thisMonth, to: targetMonth).month ?? 0) + 1
            }
        }

        var suggested: Money?
        if let monthsLeft, monthsLeft > 0, remaining.isPositive {
            let months = Int64(monthsLeft)
            suggested = Money(minorUnits: (remaining.minorUnits + months - 1) / months, currency: target.currency)
        }

        return SavingsProgress(
            target: target,
            saved: saved,
            remaining: remaining,
            fraction: fraction,
            isReached: isReached,
            monthsLeft: monthsLeft,
            suggestedMonthly: suggested,
            isOverdue: isOverdue
        )
    }

    /// Validates a contribution (`isWithdrawal == false`) or withdrawal.
    /// - Parameters:
    ///   - amount: unsigned amount entered by the user.
    ///   - saved: what is currently saved for the goal.
    /// - Returns: the signed amount to store.
    public static func signedEntry(amount: Money, isWithdrawal: Bool, saved: Money) throws -> Money {
        guard amount.isPositive else { throw LedgerValidationError.nonPositiveAmount }
        guard amount.currency == saved.currency else {
            throw LedgerValidationError.currencyMismatch(walletCurrency: saved.currency.code, amountCurrency: amount.currency.code)
        }
        guard isWithdrawal else { return amount }
        guard amount.minorUnits <= saved.minorUnits else { throw LedgerValidationError.withdrawalExceedsSavings }
        return try amount.negated()
    }
}

/// Budget alert rules.
public enum BudgetAlertRules {
    /// Thresholds a budget can alert at. An empty selection turns alerts off.
    public static let allowedThresholds: [Int] = [50, 80, 90, 100]
    public static let defaultThresholds: [Int] = [80, 100]

    /// Sorted, without duplicates; throws for a value outside `allowedThresholds`.
    public static func normalizedThresholds(_ thresholds: [Int]) throws -> [Int] {
        let unique = Set(thresholds)
        guard unique.isSubset(of: allowedThresholds) else { throw LedgerValidationError.invalidAlertThresholds }
        return unique.sorted()
    }

    /// Thresholds (percent of the available amount) reached by `progress` that
    /// have not been alerted yet, lowest first. When nothing is available
    /// (zero or negative after rollover), any spending counts as 100 %.
    public static func newlyReachedThresholds(
        progress: BudgetProgress,
        thresholds: [Int],
        alreadyAlerted: Set<Int>
    ) -> [Int] {
        guard progress.status != .notStarted, progress.status != .ended else { return [] }
        let percentUsed: Decimal
        if let utilization = progress.utilization {
            percentUsed = utilization * 100
        } else {
            percentUsed = progress.spent.isPositive ? 100 : 0
        }
        return Set(thresholds)
            .filter { $0 > 0 && Decimal($0) <= percentUsed && !alreadyAlerted.contains($0) }
            .sorted()
    }

    /// Identifies one alert so it is sent at most once per budget period.
    public static func alertKey(budgetID: UUID, window: BudgetWindow, threshold: Int) -> String {
        alertKeyPrefix(budgetID: budgetID, window: window) + String(threshold)
    }

    /// The part of `alertKey` shared by every threshold of one budget period.
    static func alertKeyPrefix(budgetID: UUID, window: BudgetWindow) -> String {
        "budget-\(budgetID.uuidString)-\(window.firstDay.rawValue)-"
    }

    /// The remembered alert keys still needed: those of each budget's current
    /// period, and every key of a budget whose period couldn't be worked out
    /// (`unreadable`), so a read error never makes an alert repeat. Keys of past
    /// periods and of deleted budgets are dropped, so the list stays small.
    public static func keysToKeep(
        _ sent: Set<String>,
        currentWindows: [UUID: BudgetWindow],
        unreadable: Set<UUID> = []
    ) -> Set<String> {
        let current = currentWindows.map { alertKeyPrefix(budgetID: $0.key, window: $0.value) }
        let kept = unreadable.map { "budget-\($0.uuidString)-" }
        return sent.filter { key in
            current.contains { key.hasPrefix($0) } || kept.contains { key.hasPrefix($0) }
        }
    }
}
