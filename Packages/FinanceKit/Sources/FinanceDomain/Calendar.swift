import Foundation

/// A half-open date interval `[start, end)`.
/// The end is exclusive, so consecutive months never share an instant.
public struct DateRange: Hashable, Sendable, Codable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) throws {
        guard start < end else { throw FinancialError.invalidDateRange }
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// A calendar day encoded as `yyyymmdd`, e.g. 20261012.
///
/// Stored next to each transaction's timestamp, computed in the user's time
/// zone at entry time. Grouping by day and period boundaries use the day key,
/// so a lunch logged at 12:30 in Hanoi stays on the same day when the user
/// later travels to another time zone.
public struct DayKey: RawRepresentable, Hashable, Comparable, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(year: Int, month: Int, day: Int) {
        self.rawValue = year * 10_000 + month * 100 + day
    }

    public var year: Int { rawValue / 10_000 }
    public var month: Int { (rawValue / 100) % 100 }
    public var day: Int { rawValue % 100 }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The periods offered by the dashboard, reports and budgets.
public enum ReportingPeriod: Hashable, Sendable {
    case thisWeek
    case thisMonth
    case lastMonth
    case thisYear
    /// Whole days from `firstDay` through `lastDay`, both inclusive.
    case custom(firstDay: Date, lastDay: Date)
}

/// The single source of truth for mapping instants to days, weeks, months and years.
///
/// Policy: Gregorian calendar, the user's current time zone, weeks start on
/// Monday (ISO 8601 style, the common convention in Vietnam).
public struct CalendarPolicy: Hashable, Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone = .autoupdatingCurrent, firstWeekday: Int = 2) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        self.calendar = calendar
    }

    public func dayKey(for date: Date) -> DayKey {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// Midnight at the start of the given day in this policy's time zone.
    public func startOfDay(_ key: DayKey) -> Date? {
        calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day))
    }

    public func range(for period: ReportingPeriod, relativeTo reference: Date) throws -> DateRange {
        switch period {
        case .thisWeek:
            return try interval(of: .weekOfYear, containing: reference)
        case .thisMonth:
            return try interval(of: .month, containing: reference)
        case .lastMonth:
            let thisMonth = try interval(of: .month, containing: reference)
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: thisMonth.start) else {
                throw FinancialError.invalidDateRange
            }
            return try interval(of: .month, containing: dayBefore)
        case .thisYear:
            return try interval(of: .year, containing: reference)
        case .custom(let firstDay, let lastDay):
            let start = calendar.startOfDay(for: firstDay)
            let lastDayStart = calendar.startOfDay(for: lastDay)
            guard let end = calendar.date(byAdding: .day, value: 1, to: lastDayStart) else {
                throw FinancialError.invalidDateRange
            }
            return try DateRange(start: start, end: end)
        }
    }

    private func interval(of component: Calendar.Component, containing date: Date) throws -> DateRange {
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            throw FinancialError.invalidDateRange
        }
        return try DateRange(start: interval.start, end: interval.end)
    }
}
