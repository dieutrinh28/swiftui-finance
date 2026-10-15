import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

@MainActor
@Suite("Contribution and record-occurrence form models")
struct ContributionAndRecordFormModelTests {
    private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }

    private func goal(_ fixture: FormFixture) throws -> SavingsGoal {
        try fixture.savings.create(SavingsGoalDraft(
            name: "Trip", target: vnd(10_000_000), iconName: "airplane", colorIdentifier: "teal"
        ))
    }

    @Test func contributionNeedsAPositiveAmount() throws {
        let fixture = try FormFixture()
        let trip = try goal(fixture)
        let model = ContributionFormModel(goal: trip, isWithdrawal: false, service: fixture.savings,
                                          now: FormFixture.now, parser: FormFixture.parser)
        #expect(model.currency == .vnd)
        #expect(!model.canSave)
        model.amountText = "0"
        #expect(!model.canSave)
        model.amountText = "500.000"
        #expect(model.canSave)
        #expect(model.save())
        #expect(try fixture.savings.progress(of: trip, at: FormFixture.now).saved == vnd(500_000))
    }

    @Test func withdrawingMoreThanSavedIsReported() throws {
        let fixture = try FormFixture()
        let trip = try goal(fixture)
        try fixture.savings.addEntry(to: trip, amount: vnd(200_000), isWithdrawal: false, date: FormFixture.now)

        let model = ContributionFormModel(goal: trip, isWithdrawal: true, service: fixture.savings,
                                          now: FormFixture.now, parser: FormFixture.parser)
        model.amountText = "300.000"
        #expect(model.canSave)                       // the limit is the service's rule
        #expect(!model.save())
        #expect(model.failure != nil)
        #expect(try fixture.savings.progress(of: trip, at: FormFixture.now).saved == vnd(200_000))
        model.clearFailure()
        #expect(model.failure == nil)
    }

    private func dueItem(_ fixture: FormFixture, _ draft: RecurringDraft) throws -> DueOccurrence {
        try fixture.recurring.create(draft)
        return try #require(try fixture.recurring.dueOccurrences(at: FormFixture.now).first)
    }

    private var lastWeek: Date {
        PreviewFixtures.calendarPolicy.calendar.date(byAdding: .day, value: -7, to: FormFixture.now)!
    }

    @Test func recordingAVariableBill() throws {
        let fixture = try FormFixture()
        let item = try dueItem(fixture, RecurringDraft(
            name: "Electricity", kind: .expense, amount: vnd(600_000), wallet: fixture.cash,
            category: try fixture.category("expense.housing"),
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: lastWeek)
        ))
        let model = RecordOccurrenceFormModel(item: item, service: fixture.recurring, parser: FormFixture.parser)
        #expect(model.amountText == FormFixture.parser.editingText(for: vnd(600_000)))
        #expect(!model.needsReceivedAmount)
        #expect(model.loadFailure == nil)

        model.amountText = "750.000"
        #expect(model.canSave)
        #expect(model.save())
        let recorded = try #require(try fixture.recurring.recordedTransactions(of: item.recurring).first)
        #expect(recorded.displayAmount == vnd(750_000))
        #expect(try fixture.recurring.dueOccurrences(at: FormFixture.now).isEmpty)
    }

    @Test func crossCurrencyTransferNeedsTheReceivedAmount() throws {
        let fixture = try FormFixture()
        let item = try dueItem(fixture, RecurringDraft(
            name: "Savings in USD", kind: .transfer, amount: vnd(2_500_000), wallet: fixture.cash,
            category: nil, destination: fixture.usd, receivedAmount: Money(minorUnits: 10_000, currency: .usd),
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: lastWeek)
        ))
        let model = RecordOccurrenceFormModel(item: item, service: fixture.recurring, parser: FormFixture.parser)
        #expect(model.needsReceivedAmount)
        #expect(model.crossCurrencyDestination?.id == fixture.usd.id)
        #expect(!model.receivedText.isEmpty)          // prefilled from the item
        #expect(model.canSave)

        model.receivedText = ""
        #expect(!model.canSave)
        model.receivedText = FormFixture.parser.editingText(for: Money(minorUnits: 9_800, currency: .usd))
        #expect(model.save())
    }
}
