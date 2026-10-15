import Foundation

/// How often a recurring transaction repeats. Raw values are persisted.
public enum RecurrenceFrequency: String, CaseIterable, Codable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    var calendarComponent: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

/// When a recurring transaction is due.
public struct RecurrenceSchedule: Sendable, Equatable {
    public var frequency: RecurrenceFrequency
    /// Every `interval` days/weeks/months/years (1…365).
    public var interval: Int
    public var startDate: Date
    /// Inclusive last day; nil repeats forever.
    public var endDate: Date?

    public init(frequency: RecurrenceFrequency, interval: Int = 1, startDate: Date, endDate: Date? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// One due date of a recurring transaction.
public struct Occurrence: Sendable, Hashable {
    /// Midnight at the start of the due day.
    public let date: Date
    public let day: DayKey
    /// 0 for the first occurrence.
    public let index: Int
}

/// Recurrence rules.
///
/// - Occurrences are anchored to the start date, so a monthly item on the 31st
///   falls on the last day of shorter months and returns to the 31st afterwards
///   (31 Jan → 28 Feb → 31 Mar), and never drifts.
/// - Every occurrence has a stable key (`occurrenceKey`). It is stored on the
///   transaction recorded for it and on the definition once handled, so the
///   same occurrence can never be recorded twice.
/// - There is no background processing: due occurrences are found when the app
///   is opened, and the user records or skips them.
public enum RecurrenceRules {
    public static let intervalRange = 1...365
    /// Guards loops over very long schedules.
    static let maximumIterations = 20_000

    public static func validate(_ schedule: RecurrenceSchedule, policy: CalendarPolicy) throws {
        guard intervalRange.contains(schedule.interval) else {
            throw LedgerValidationError.invalidRecurrence
        }
        if let end = schedule.endDate,
           policy.calendar.startOfDay(for: end) < policy.calendar.startOfDay(for: schedule.startDate) {
            throw LedgerValidationError.invalidRecurrence
        }
    }

    /// The `index`-th occurrence, or nil if it falls after the end date.
    public static func occurrence(_ index: Int, of schedule: RecurrenceSchedule, policy: CalendarPolicy) -> Occurrence? {
        let calendar = policy.calendar
        let start = calendar.startOfDay(for: schedule.startDate)
        guard index >= 0,
              let shifted = calendar.date(byAdding: schedule.frequency.calendarComponent,
                                          value: index * schedule.interval, to: start)
        else { return nil }
        let date = calendar.startOfDay(for: shifted)
        if let end = schedule.endDate, date > calendar.startOfDay(for: end) { return nil }
        return Occurrence(date: date, day: policy.dayKey(for: date), index: index)
    }

    /// Occurrences whose day lies between `from` and `through` (both days inclusive), oldest first.
    public static func occurrences(
        of schedule: RecurrenceSchedule,
        from: Date,
        through: Date,
        policy: CalendarPolicy,
        limit: Int = 500
    ) -> [Occurrence] {
        let first = policy.dayKey(for: from)
        let last = policy.dayKey(for: through)
        var result: [Occurrence] = []
        var index = 0
        while index < maximumIterations, result.count < limit,
              let candidate = Self.occurrence(index, of: schedule, policy: policy),
              candidate.day <= last {
            if candidate.day >= first { result.append(candidate) }
            index += 1
        }
        return result
    }

    /// The first occurrence on or after the day of `reference`.
    public static func next(of schedule: RecurrenceSchedule, onOrAfter reference: Date, policy: CalendarPolicy) -> Occurrence? {
        let day = policy.dayKey(for: reference)
        var index = 0
        while index < maximumIterations, let candidate = Self.occurrence(index, of: schedule, policy: policy) {
            if candidate.day >= day { return candidate }
            index += 1
        }
        return nil
    }

    public static func occurrenceKey(recurringID: UUID, day: DayKey) -> String {
        "\(recurringID.uuidString)-\(day.rawValue)"
    }

    /// The definition and day an occurrence key was made from; nil for anything else.
    public static func parseOccurrenceKey(_ key: String) -> (recurringID: UUID, day: DayKey)? {
        let parts = key.split(separator: "-")
        guard parts.count == 6,
              let id = UUID(uuidString: parts[0..<5].joined(separator: "-")),
              let raw = Int(parts[5]), (1000_01_01...9999_12_31).contains(raw)
        else { return nil }
        return (id, DayKey(rawValue: raw))
    }

    /// Reminder times for the next `count` occurrences after `now`:
    /// each occurrence day at `minutesAfterMidnight`.
    public static func reminderDates(
        of schedule: RecurrenceSchedule,
        minutesAfterMidnight: Int,
        after now: Date,
        count: Int,
        policy: CalendarPolicy
    ) -> [(occurrence: Occurrence, fireDate: Date)] {
        var result: [(occurrence: Occurrence, fireDate: Date)] = []
        var index = 0
        while index < maximumIterations, result.count < count,
              let candidate = Self.occurrence(index, of: schedule, policy: policy) {
            if let fire = policy.calendar.date(byAdding: .minute, value: minutesAfterMidnight, to: candidate.date),
               fire > now {
                result.append((occurrence: candidate, fireDate: fire))
            }
            index += 1
        }
        return result
    }
}
