import Foundation
import Testing
import FinanceDomain

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }
private func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

@Suite("Recurrence rules")
struct RecurrenceRulesTests {
    private let policy = CalendarPolicy(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func monthlyOn31stDoesNotDrift() throws {
        let schedule = RecurrenceSchedule(frequency: .monthly, startDate: try date("2026-01-31T10:00:00+07:00"))
        let days = RecurrenceRules.occurrences(
            of: schedule, from: schedule.startDate, through: try date("2026-05-31T00:00:00+07:00"), policy: policy
        ).map(\.day)

        #expect(days == [day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30), day(2026, 5, 31)])
    }

    @Test func weeklyEveryTwoWeeksAndEndDate() throws {
        let schedule = RecurrenceSchedule(
            frequency: .weekly, interval: 2,
            startDate: try date("2026-10-01T00:00:00+07:00"),
            endDate: try date("2026-10-29T00:00:00+07:00")
        )
        let days = RecurrenceRules.occurrences(
            of: schedule, from: schedule.startDate, through: try date("2026-12-31T00:00:00+07:00"), policy: policy
        ).map(\.day)

        #expect(days == [day(2026, 10, 1), day(2026, 10, 15), day(2026, 10, 29)])
    }

    @Test func yearlyOnLeapDay() throws {
        let schedule = RecurrenceSchedule(frequency: .yearly, startDate: try date("2028-02-29T00:00:00+07:00"))
        #expect(RecurrenceRules.occurrence(1, of: schedule, policy: policy)?.day == day(2029, 2, 28))
        #expect(RecurrenceRules.occurrence(4, of: schedule, policy: policy)?.day == day(2032, 2, 29))
    }

    @Test func occurrencesInAWindowOnly() throws {
        let schedule = RecurrenceSchedule(frequency: .daily, startDate: try date("2026-10-01T00:00:00+07:00"))
        let window = RecurrenceRules.occurrences(
            of: schedule, from: try date("2026-10-10T12:00:00+07:00"), through: try date("2026-10-12T23:00:00+07:00"), policy: policy
        )
        #expect(window.map(\.day) == [day(2026, 10, 10), day(2026, 10, 11), day(2026, 10, 12)])
        #expect(window.first?.index == 9)
    }

    @Test func nextOccurrence() throws {
        let schedule = RecurrenceSchedule(frequency: .monthly, startDate: try date("2026-01-05T00:00:00+07:00"))
        #expect(RecurrenceRules.next(of: schedule, onOrAfter: try date("2026-10-05T20:00:00+07:00"), policy: policy)?.day
                == day(2026, 10, 5))
        #expect(RecurrenceRules.next(of: schedule, onOrAfter: try date("2026-10-06T00:00:00+07:00"), policy: policy)?.day
                == day(2026, 11, 5))

        let ended = RecurrenceSchedule(frequency: .monthly, startDate: try date("2026-01-05T00:00:00+07:00"),
                                       endDate: try date("2026-03-01T00:00:00+07:00"))
        #expect(RecurrenceRules.next(of: ended, onOrAfter: try date("2026-10-01T00:00:00+07:00"), policy: policy) == nil)
    }

    @Test func occurrenceKeysAreStableAndUnique() {
        let id = UUID()
        #expect(RecurrenceRules.occurrenceKey(recurringID: id, day: day(2026, 10, 5))
                == RecurrenceRules.occurrenceKey(recurringID: id, day: day(2026, 10, 5)))
        #expect(RecurrenceRules.occurrenceKey(recurringID: id, day: day(2026, 10, 5))
                != RecurrenceRules.occurrenceKey(recurringID: id, day: day(2026, 11, 5)))
    }

    @Test func validation() throws {
        let start = try date("2026-10-05T00:00:00+07:00")
        #expect(throws: LedgerValidationError.invalidRecurrence) {
            try RecurrenceRules.validate(RecurrenceSchedule(frequency: .daily, interval: 0, startDate: start), policy: policy)
        }
        #expect(throws: LedgerValidationError.invalidRecurrence) {
            try RecurrenceRules.validate(
                RecurrenceSchedule(frequency: .daily, startDate: start, endDate: start.addingTimeInterval(-86_400)), policy: policy)
        }
        try RecurrenceRules.validate(RecurrenceSchedule(frequency: .daily, startDate: start, endDate: start), policy: policy)
    }

    @Test func reminderDatesAreInTheFuture() throws {
        let schedule = RecurrenceSchedule(frequency: .monthly, startDate: try date("2026-09-05T00:00:00+07:00"))
        let reminders = RecurrenceRules.reminderDates(
            of: schedule, minutesAfterMidnight: 9 * 60,
            after: try date("2026-10-05T10:00:00+07:00"), count: 2, policy: policy
        )
        // 5 Oct 09:00 has already passed at 10:00.
        #expect(reminders.map(\.occurrence.day) == [day(2026, 11, 5), day(2026, 12, 5)])
        #expect(reminders.first?.fireDate == (try date("2026-11-05T09:00:00+07:00")))
    }
}

@Suite("Savings rules")
struct SavingsRulesTests {
    private let policy = CalendarPolicy(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func progressAndSuggestedMonthly() throws {
        let progress = try SavingsRules.progress(
            target: vnd(30_000_000),
            entries: [vnd(10_000_000), vnd(2_000_000), vnd(-1_000_000)],
            targetDate: try date("2027-03-15T00:00:00+07:00"),
            reference: try date("2026-10-12T09:00:00+07:00"),
            policy: policy
        )
        #expect(progress.saved == vnd(11_000_000))
        #expect(progress.remaining == vnd(19_000_000))
        #expect(progress.monthsLeft == 6)                      // Oct, Nov, Dec, Jan, Feb, Mar
        #expect(progress.suggestedMonthly == vnd(3_166_667))   // rounded up
        #expect(!progress.isReached && !progress.isOverdue)
    }

    @Test func reachedGoalIsCappedAtOneHundredPercent() throws {
        let progress = try SavingsRules.progress(
            target: vnd(1_000_000), entries: [vnd(1_200_000)], targetDate: nil,
            reference: .now, policy: policy
        )
        #expect(progress.isReached)
        #expect(progress.fraction == 1)
        #expect(progress.remaining == vnd(0))
        #expect(progress.suggestedMonthly == nil)
    }

    @Test func overdueGoal() throws {
        let progress = try SavingsRules.progress(
            target: vnd(1_000_000), entries: [vnd(100_000)],
            targetDate: try date("2026-09-30T00:00:00+07:00"),
            reference: try date("2026-10-12T09:00:00+07:00"), policy: policy
        )
        #expect(progress.isOverdue)
        #expect(progress.monthsLeft == 0)
        #expect(progress.suggestedMonthly == nil)
    }

    @Test func withdrawalsCannotExceedSavings() throws {
        #expect(try SavingsRules.signedEntry(amount: vnd(500), isWithdrawal: false, saved: vnd(0)) == vnd(500))
        #expect(try SavingsRules.signedEntry(amount: vnd(500), isWithdrawal: true, saved: vnd(500)) == vnd(-500))
        #expect(throws: LedgerValidationError.withdrawalExceedsSavings) {
            try SavingsRules.signedEntry(amount: vnd(501), isWithdrawal: true, saved: vnd(500))
        }
        #expect(throws: LedgerValidationError.nonPositiveAmount) {
            try SavingsRules.signedEntry(amount: vnd(0), isWithdrawal: false, saved: vnd(0))
        }
    }
}

@Suite("Budget alert rules")
struct BudgetAlertRulesTests {
    private let policy = CalendarPolicy(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)

    private func progress(spent: Int64) throws -> BudgetProgress {
        try BudgetRules.progress(
            planned: vnd(1_000_000),
            schedule: BudgetSchedule(period: .monthly, startDate: try #require(ISO8601DateFormatter().date(from: "2026-10-01T00:00:00+07:00"))),
            rolloverEnabled: false,
            expenses: [BudgetExpense(amount: vnd(spent), day: day(2026, 10, 2))],
            reference: try #require(ISO8601DateFormatter().date(from: "2026-10-12T09:00:00+07:00")),
            policy: policy
        )
    }

    @Test func thresholdsAlertOncePerPeriod() throws {
        let p85 = try progress(spent: 850_000)
        #expect(BudgetAlertRules.newlyReachedThresholds(progress: p85, thresholds: [80, 100], alreadyAlerted: []) == [80])
        #expect(BudgetAlertRules.newlyReachedThresholds(progress: p85, thresholds: [80, 100], alreadyAlerted: [80]).isEmpty)

        let p120 = try progress(spent: 1_200_000)
        #expect(BudgetAlertRules.newlyReachedThresholds(progress: p120, thresholds: [100, 80], alreadyAlerted: [80]) == [100])

        let key = BudgetAlertRules.alertKey(budgetID: UUID(), window: p85.window, threshold: 80)
        #expect(key.hasSuffix("-20261001-80"))
    }
}
