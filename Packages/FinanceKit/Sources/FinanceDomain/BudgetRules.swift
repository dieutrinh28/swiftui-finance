import Foundation

/// How often a budget's planned amount repeats. Raw values are persisted.
public enum BudgetPeriod: String, CaseIterable, Codable, Sendable {
    case weekly
    case monthly
    case yearly
    /// A single window from the start date through the end date.
    case custom

    var calendarComponent: Calendar.Component? {
        switch self {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        case .custom: nil
        }
    }
}

/// When a budget applies.
public struct BudgetSchedule: Sendable, Equatable {
    public var period: BudgetPeriod
    /// The day the budget starts (time of day is ignored).
    public var startDate: Date
    /// Inclusive last day. Required for `.custom`, optional otherwise.
    public var endDate: Date?

    public init(period: BudgetPeriod, startDate: Date, endDate: Date? = nil) {
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// One budget period, as an instant range and as day keys.
public struct BudgetWindow: Hashable, Sendable {
    public let range: DateRange
    public let firstDay: DayKey
    /// Exclusive: the first day after the window.
    public let endDay: DayKey

    public func contains(_ day: DayKey) -> Bool {
        day >= firstDay && day < endDay
    }
}

/// An expense that already passed the budget's category and wallet filters.
public struct BudgetExpense: Sendable, Equatable {
    /// Unsigned amount in the expense's wallet currency.
    public var amount: Money
    public var day: DayKey

    public init(amount: Money, day: DayKey) {
        self.amount = amount
        self.day = day
    }
}

/// A plain-value view of an expense used to decide budget eligibility.
public struct ExpenseSnapshot: Sendable, Equatable {
    public var transactionID: UUID
    public var kind: TransactionKind
    public var categoryID: UUID?
    public var parentCategoryID: UUID?
    public var walletID: UUID?
    /// Unsigned amount in the wallet currency.
    public var amount: Money
    public var day: DayKey

    public init(
        transactionID: UUID,
        kind: TransactionKind,
        categoryID: UUID?,
        parentCategoryID: UUID? = nil,
        walletID: UUID?,
        amount: Money,
        day: DayKey
    ) {
        self.transactionID = transactionID
        self.kind = kind
        self.categoryID = categoryID
        self.parentCategoryID = parentCategoryID
        self.walletID = walletID
        self.amount = amount
        self.day = day
    }
}

/// The state of a budget in the period that contains the reference date.
public struct BudgetProgress: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case notStarted
        case onTrack
        case nearLimit
        case overBudget
        case ended
    }

    public let window: BudgetWindow
    public let planned: Money
    /// Unused (positive) or overspent (negative) amount from earlier periods.
    /// Always zero when rollover is off.
    public let carriedOver: Money
    /// planned + carriedOver
    public let available: Money
    public let spent: Money
    /// available − spent; negative when over budget.
    public let remaining: Money
    /// spent ÷ available (0.625 = 62.5 %); nil when nothing is available.
    public let utilization: Decimal?
    /// Days left in the window, including today. 0 outside the window.
    public let daysLeft: Int
    /// remaining ÷ daysLeft, rounded down; zero when nothing remains; nil outside the window.
    public let dailyAllowance: Money?
    /// Expenses in this window that match the budget's categories but use another currency.
    public let excludedOtherCurrencyCount: Int
    public let status: Status
}

/// Budget rules. See docs/ARCHITECTURE.md, "Budgets".
///
/// - Only expenses count; income and transfers never do.
/// - An expense counts when its category (or that category's parent) is one of
///   the budget's categories and, if the budget is limited to wallets, its
///   wallet is one of them. Each transaction counts at most once per budget.
/// - Budgets are independent: two budgets sharing a category both count it.
/// - Only expenses in the budget's currency count; others are reported, not converted.
/// - Periods follow `CalendarPolicy` (Monday weeks, calendar months and years)
///   and use the transaction's day key. The first window starts on the start day.
/// - Rollover: when on, the sum of (planned − spent) over all completed periods
///   is added to the current period. Overspending therefore reduces later periods.
public enum BudgetRules {
    /// At or above this utilization a budget is "near its limit".
    public static var nearLimitRatio: Decimal { Decimal(8) / Decimal(10) }

    /// Guards against runaway loops (about 96 years of weekly windows).
    static let maximumWindows = 5_000

    public static func validateSchedule(_ schedule: BudgetSchedule, policy: CalendarPolicy) throws {
        if schedule.period == .custom, schedule.endDate == nil {
            throw LedgerValidationError.budgetNeedsEndDate
        }
        if let end = schedule.endDate,
           policy.calendar.startOfDay(for: end) < policy.calendar.startOfDay(for: schedule.startDate) {
            throw FinancialError.invalidDateRange
        }
    }

    /// Snapshots that count towards a budget, each transaction at most once.
    /// - Parameter walletIDs: empty means every wallet.
    public static func eligibleSnapshots(
        _ snapshots: [ExpenseSnapshot],
        categoryIDs: Set<UUID>,
        walletIDs: Set<UUID>
    ) -> [ExpenseSnapshot] {
        var seen = Set<UUID>()
        return snapshots.filter { snapshot in
            guard snapshot.kind == .expense else { return false }
            let matchesCategory = snapshot.categoryID.map { categoryIDs.contains($0) } ?? false
            let matchesParent = snapshot.parentCategoryID.map { categoryIDs.contains($0) } ?? false
            guard matchesCategory || matchesParent else { return false }
            if !walletIDs.isEmpty {
                guard let walletID = snapshot.walletID, walletIDs.contains(walletID) else { return false }
            }
            return seen.insert(snapshot.transactionID).inserted
        }
    }

    /// Expenses that count towards a budget, each transaction at most once.
    /// - Parameter walletIDs: empty means every wallet.
    public static func eligibleExpenses(
        _ snapshots: [ExpenseSnapshot],
        categoryIDs: Set<UUID>,
        walletIDs: Set<UUID>
    ) -> [BudgetExpense] {
        eligibleSnapshots(snapshots, categoryIDs: categoryIDs, walletIDs: walletIDs)
            .map { BudgetExpense(amount: $0.amount, day: $0.day) }
    }

    /// Every window from the first one through the one containing `reference`
    /// (or the last one if the budget has ended). Never empty.
    public static func windows(
        for schedule: BudgetSchedule,
        through reference: Date,
        policy: CalendarPolicy
    ) throws -> [BudgetWindow] {
        try validateSchedule(schedule, policy: policy)
        let calendar = policy.calendar
        let start = calendar.startOfDay(for: schedule.startDate)
        let hardEnd: Date? = try schedule.endDate.map { end in
            guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) else {
                throw FinancialError.invalidDateRange
            }
            return next
        }

        guard let component = schedule.period.calendarComponent else {
            guard let hardEnd else { throw LedgerValidationError.budgetNeedsEndDate }
            return [try window(from: start, to: hardEnd, policy: policy)]
        }

        var result: [BudgetWindow] = []
        var cursor = start
        while result.count < maximumWindows {
            guard let interval = calendar.dateInterval(of: component, for: cursor) else {
                throw FinancialError.invalidDateRange
            }
            var end = interval.end
            if let hardEnd, hardEnd < end { end = hardEnd }
            result.append(try window(from: cursor, to: end, policy: policy))

            if reference < end { break }
            if let hardEnd, end >= hardEnd { break }
            cursor = end
        }
        return result
    }

    public static func progress(
        planned: Money,
        schedule: BudgetSchedule,
        rolloverEnabled: Bool,
        expenses: [BudgetExpense],
        reference: Date,
        policy: CalendarPolicy
    ) throws -> BudgetProgress {
        guard planned.isPositive else { throw LedgerValidationError.nonPositiveAmount }
        let windows = try windows(for: schedule, through: reference, policy: policy)
        guard let current = windows.last else { throw FinancialError.invalidDateRange }
        let currentIndex = windows.count - 1
        let currency = planned.currency

        var spentPerWindow = Array(repeating: Money.zero(currency), count: windows.count)
        var excluded = 0
        for expense in expenses {
            guard let index = windows.firstIndex(where: { $0.contains(expense.day) }) else { continue }
            guard expense.amount.currency == currency else {
                if index == currentIndex { excluded += 1 }
                continue
            }
            spentPerWindow[index] = try spentPerWindow[index].adding(expense.amount)
        }

        var carriedOver = Money.zero(currency)
        if rolloverEnabled {
            for index in 0..<currentIndex {
                carriedOver = try carriedOver.adding(planned.subtracting(spentPerWindow[index]))
            }
        }

        let available = try planned.adding(carriedOver)
        let spent = spentPerWindow[currentIndex]
        let remaining = try available.subtracting(spent)
        let utilization: Decimal? = try (available.isPositive ? spent.ratio(to: available) : nil)

        let calendar = policy.calendar
        let isInside = current.range.contains(reference)
        let daysLeft: Int
        if isInside {
            daysLeft = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: current.range.end).day ?? 0
        } else if reference < current.range.start {
            daysLeft = calendar.dateComponents([.day], from: current.range.start, to: current.range.end).day ?? 0
        } else {
            daysLeft = 0
        }

        var dailyAllowance: Money?
        if isInside {
            if remaining.isPositive, daysLeft > 0 {
                dailyAllowance = Money(minorUnits: remaining.minorUnits / Int64(daysLeft), currency: currency)
            } else {
                dailyAllowance = .zero(currency)
            }
        }

        let status: BudgetProgress.Status
        if reference < current.range.start {
            status = .notStarted
        } else if reference >= current.range.end {
            status = .ended
        } else if spent.minorUnits > available.minorUnits {
            status = .overBudget
        } else if let utilization, utilization >= nearLimitRatio {
            status = .nearLimit
        } else {
            status = .onTrack
        }

        return BudgetProgress(
            window: current,
            planned: planned,
            carriedOver: carriedOver,
            available: available,
            spent: spent,
            remaining: remaining,
            utilization: utilization,
            daysLeft: daysLeft,
            dailyAllowance: dailyAllowance,
            excludedOtherCurrencyCount: excluded,
            status: status
        )
    }

    private static func window(from start: Date, to end: Date, policy: CalendarPolicy) throws -> BudgetWindow {
        BudgetWindow(
            range: try DateRange(start: start, end: end),
            firstDay: policy.dayKey(for: start),
            endDay: policy.dayKey(for: end)
        )
    }
}
