import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

@MainActor
@Suite("Recurring form model")
struct RecurringFormModelTests {
    @Test func defaultsStartTodayMonthlyWithoutReminder() throws {
        let fixture = try FormFixture()
        let model = fixture.recurringModel(.create)
        let policy = PreviewFixtures.calendarPolicy

        #expect(!model.isEditing)
        #expect(model.frequency == .monthly && model.interval == 1)
        #expect(policy.dayKey(for: model.startDate) == policy.dayKey(for: FormFixture.now))
        #expect(!model.reminderEnabled)
        #expect(model.reminderMinutes == 540)
        #expect(!model.canSave)
    }

    @Test func canSaveAndKindSwitch() throws {
        let fixture = try FormFixture()
        let model = fixture.recurringModel(.create)
        model.name = "Rent"
        model.selectDefaultWalletIfNeeded(from: fixture.allWallets)
        model.amountText = "6.000.000"
        #expect(!model.canSave)                       // no category

        model.category = try fixture.category("expense.housing")
        #expect(model.canSave)

        model.kind = .income
        #expect(model.category == nil)
        #expect(!model.canSave)

        model.category = try fixture.category("income.salary")
        model.interval = 0
        #expect(!model.canSave)
    }

    @Test func reminderTimeRoundTrips() throws {
        let fixture = try FormFixture()
        let model = fixture.recurringModel(.create)
        let calendar = PreviewFixtures.calendarPolicy.calendar
        model.reminderTime = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: FormFixture.now)!
        #expect(model.reminderMinutes == 20 * 60 + 30)
        #expect(calendar.component(.hour, from: model.reminderTime) == 20)
    }

    @Test func nextOccurrencePreview() throws {
        let fixture = try FormFixture()
        let model = fixture.recurringModel(.create)
        model.startDate = PreviewFixtures.calendarPolicy.calendar.date(byAdding: .day, value: -20, to: FormFixture.now)!
        // Started 22 September; next monthly occurrence on or after 12 October is 22 October.
        let next = try #require(model.nextOccurrence)
        #expect(PreviewFixtures.calendarPolicy.dayKey(for: next) == DayKey(year: 2026, month: 10, day: 22))
    }

    @Test func saveCreatesAndEditUpdates() throws {
        let fixture = try FormFixture()
        let model = fixture.recurringModel(.create)
        model.name = "Gym"
        model.wallet = fixture.cash
        model.amountText = "500000"
        model.category = try fixture.category("expense.fitness")
        model.reminderEnabled = true
        #expect(model.save())

        let saved = try #require(try fixture.context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(saved.name == "Gym")
        #expect(saved.reminderEnabled)

        let editor = fixture.recurringModel(.edit(saved))
        #expect(editor.isEditing)
        #expect(editor.amountText == "500000")
        #expect(editor.wallet?.id == fixture.cash.id)
        #expect(editor.category?.seedKey == "expense.fitness")

        editor.amountText = "550000"
        editor.frequency = .weekly
        #expect(editor.save())
        #expect(saved.amountMinorUnits == 550_000)
        #expect(saved.frequency == .weekly)
        #expect(try fixture.context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 1)
    }

    @Test func failureIsReported() throws {
        let fixture = try FormFixture()
        let model = fixture.recurringModel(.create)
        model.name = "Rent"
        model.wallet = fixture.cash
        model.amountText = "1000"

        #expect(!model.save())
        #expect(model.failure as? LedgerValidationError == .missingCategory)
        #expect(try fixture.context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 0)
    }
}
