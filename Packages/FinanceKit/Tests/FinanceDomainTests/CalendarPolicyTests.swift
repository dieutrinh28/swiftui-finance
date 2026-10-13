import Foundation
import Testing
import FinanceDomain

@Suite("Calendar policy")
struct CalendarPolicyTests {
    private let vietnam = CalendarPolicy(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)
    private let utc = CalendarPolicy(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func monthIsHalfOpenInLocalTime() throws {
        let range = try vietnam.range(for: .thisMonth, relativeTo: date("2026-01-31T10:00:00+07:00"))

        #expect(range.start == (try date("2026-01-01T00:00:00+07:00")))
        #expect(range.end == (try date("2026-02-01T00:00:00+07:00")))
        #expect(range.contains(try date("2026-01-31T23:59:59+07:00")))
        #expect(!range.contains(try date("2026-02-01T00:00:00+07:00")))
    }

    @Test func lastMonthCrossesYearBoundary() throws {
        let range = try vietnam.range(for: .lastMonth, relativeTo: date("2026-01-15T08:00:00+07:00"))

        #expect(range.start == (try date("2025-12-01T00:00:00+07:00")))
        #expect(range.end == (try date("2026-01-01T00:00:00+07:00")))
    }

    @Test func lastMonthFromMarchHandlesFebruary() throws {
        let range = try vietnam.range(for: .lastMonth, relativeTo: date("2028-03-31T08:00:00+07:00"))

        #expect(range.start == (try date("2028-02-01T00:00:00+07:00")))
        #expect(range.end == (try date("2028-03-01T00:00:00+07:00")))
    }

    @Test func weekStartsOnMonday() throws {
        // Sunday 11 Oct 2026 belongs to the week starting Monday 5 Oct.
        let range = try vietnam.range(for: .thisWeek, relativeTo: date("2026-10-11T20:00:00+07:00"))

        #expect(range.start == (try date("2026-10-05T00:00:00+07:00")))
        #expect(range.end == (try date("2026-10-12T00:00:00+07:00")))
    }

    @Test func yearRange() throws {
        let range = try vietnam.range(for: .thisYear, relativeTo: date("2026-06-15T12:00:00+07:00"))

        #expect(range.start == (try date("2026-01-01T00:00:00+07:00")))
        #expect(range.end == (try date("2027-01-01T00:00:00+07:00")))
    }

    @Test func customRangeIncludesBothDays() throws {
        let range = try vietnam.range(
            for: .custom(firstDay: date("2026-10-01T15:00:00+07:00"), lastDay: date("2026-10-03T09:00:00+07:00")),
            relativeTo: date("2026-10-12T00:00:00+07:00")
        )

        #expect(range.start == (try date("2026-10-01T00:00:00+07:00")))
        #expect(range.end == (try date("2026-10-04T00:00:00+07:00")))
    }

    @Test func reversedCustomRangeIsRejected() throws {
        let first = try date("2026-10-05T00:00:00+07:00")
        let last = try date("2026-10-01T00:00:00+07:00")

        #expect(throws: FinancialError.invalidDateRange) {
            try vietnam.range(for: .custom(firstDay: first, lastDay: last), relativeTo: first)
        }
    }

    @Test func dayKeyUsesPolicyTimeZone() throws {
        // 00:30 on 12 Oct in Vietnam is still 11 Oct in UTC.
        let instant = try date("2026-10-12T00:30:00+07:00")

        #expect(vietnam.dayKey(for: instant) == DayKey(year: 2026, month: 10, day: 12))
        #expect(utc.dayKey(for: instant) == DayKey(year: 2026, month: 10, day: 11))
    }

    @Test func dayKeyComponentsAndOrdering() {
        let key = DayKey(year: 2026, month: 2, day: 9)

        #expect(key.rawValue == 20_260_209)
        #expect(key.year == 2026 && key.month == 2 && key.day == 9)
        #expect(DayKey(year: 2025, month: 12, day: 31) < key)
    }

    @Test func dateRangeRejectsEmptyInterval() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(throws: FinancialError.invalidDateRange) {
            try DateRange(start: now, end: now)
        }
    }
}
