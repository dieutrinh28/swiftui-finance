import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

@MainActor
@Suite("Savings goal form model")
struct SavingsGoalFormModelTests {
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        PreviewFixtures.calendarPolicy.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeGoal(
        _ fixture: FormFixture,
        target: Money = Money(minorUnits: 30_000_000, currency: .vnd),
        wallet: Wallet? = nil,
        saved: Int64 = 0
    ) throws -> SavingsGoal {
        let goal = try fixture.savings.create(SavingsGoalDraft(
            name: "Emergency fund", target: target, targetDate: Self.day(2027, 3, 31),
            linkedWallet: wallet, iconName: "cross.case", colorIdentifier: "teal"
        ))
        if saved > 0 {
            try fixture.savings.addEntry(
                to: goal, amount: Money(minorUnits: saved, currency: target.currency),
                isWithdrawal: false, date: FormFixture.now
            )
        }
        return goal
    }

    @Test func defaults() throws {
        let fixture = try FormFixture()
        let model = fixture.savingsModel(.create)
        let policy = PreviewFixtures.calendarPolicy

        #expect(!model.isEditing)
        #expect(model.currency == .vnd)
        #expect(!model.currencyLocked)
        #expect(!model.showsCurrencyPicker)            // VND is the only enabled currency
        #expect(model.hasTargetDate)
        #expect(policy.dayKey(for: model.targetDate) == DayKey(year: 2027, month: 10, day: 12))
        #expect(model.estimate == nil)
        #expect(!model.canSave)
    }

    @Test func canSaveNeedsNameAndPositiveTarget() throws {
        let fixture = try FormFixture()
        let model = fixture.savingsModel(.create)
        model.targetText = "30.000.000"
        #expect(!model.canSave)                       // no name

        model.name = "Trip"
        #expect(model.canSave)

        model.targetText = "0"
        #expect(!model.canSave)
        model.targetText = "abc"
        #expect(!model.canSave)
        model.name = "   "
        model.targetText = "1.000.000"
        #expect(!model.canSave)
    }

    @Test func liveEstimate() throws {
        let fixture = try FormFixture()
        let model = fixture.savingsModel(.create)
        model.targetText = "12.000.000"
        model.targetDate = Self.day(2027, 3, 31)

        // October 2026 through March 2027 is six months.
        let estimate = try #require(model.estimate)
        #expect(estimate.monthsLeft == 6)
        #expect(estimate.suggestedMonthly == Money(minorUnits: 2_000_000, currency: .vnd))

        model.hasTargetDate = false
        let open = try #require(model.estimate)
        #expect(open.monthsLeft == nil)
        #expect(open.suggestedMonthly == nil)
    }

    @Test func estimateCountsMoneyAlreadySaved() throws {
        let fixture = try FormFixture()
        let goal = try makeGoal(fixture, saved: 6_000_000)
        let editor = fixture.savingsModel(.edit(goal))

        let estimate = try #require(editor.estimate)
        #expect(estimate.saved == Money(minorUnits: 6_000_000, currency: .vnd))
        #expect(estimate.suggestedMonthly == Money(minorUnits: 4_000_000, currency: .vnd))   // 24M over 6 months
    }

    @Test func linkedWalletFollowsCurrency() throws {
        let fixture = try FormFixture()
        let model = fixture.savingsModel(.create)

        model.linkedWallet = fixture.usd
        #expect(model.linkedWallet == nil)            // other currency is ignored
        model.linkedWallet = fixture.bank
        #expect(model.linkedWallet?.id == fixture.bank.id)
        #expect(model.availableWallets(from: fixture.allWallets).map(\.id) == [fixture.cash.id, fixture.bank.id])

        model.currency = .usd                         // allowed: nothing saved yet
        #expect(model.currency == .usd)
        #expect(model.linkedWallet == nil)            // bank is VND, so it is dropped
        #expect(model.availableWallets(from: fixture.allWallets).map(\.id) == [fixture.usd.id])
    }

    @Test func currencyLockedOnceMoneyIsSaved() throws {
        let fixture = try FormFixture()
        let goal = try makeGoal(fixture, wallet: fixture.bank, saved: 5_000_000)
        let editor = fixture.savingsModel(.edit(goal))

        #expect(editor.isEditing)
        #expect(editor.currencyLocked)
        #expect(editor.linkedWallet?.id == fixture.bank.id)
        #expect(editor.targetText == "30000000")

        editor.currency = .usd
        #expect(editor.currency == .vnd)
        #expect(editor.linkedWallet?.id == fixture.bank.id)
    }

    @Test func pickerShownForGoalInAnotherCurrency() throws {
        let fixture = try FormFixture()
        let goal = try makeGoal(fixture, target: Money(minorUnits: 100_000, currency: .usd))
        let editor = fixture.savingsModel(.edit(goal))

        // A legacy USD goal keeps its currency selectable next to VND.
        #expect(editor.currencyOptions == [.vnd, .usd])
        #expect(editor.showsCurrencyPicker)
        #expect(!editor.currencyLocked)
    }

    @Test func saveCreatesAndEditUpdates() throws {
        let fixture = try FormFixture()
        let model = fixture.savingsModel(.create)
        model.name = "Laptop"
        model.targetText = "25.000.000"
        model.hasTargetDate = false
        model.linkedWallet = fixture.cash
        #expect(model.save())

        let saved = try #require(try fixture.context.fetch(FetchDescriptor<SavingsGoal>()).first)
        #expect(saved.name == "Laptop")
        #expect(saved.targetAmountMinorUnits == 25_000_000)
        #expect(saved.targetDate == nil)
        #expect(saved.linkedWalletID == fixture.cash.id)

        let editor = fixture.savingsModel(.edit(saved))
        editor.targetText = "28.000.000"
        editor.linkedWallet = nil
        #expect(editor.save())
        #expect(saved.targetAmountMinorUnits == 28_000_000)
        #expect(saved.linkedWalletID == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<SavingsGoal>()) == 1)
    }

    @Test func failureIsReportedAndCleared() throws {
        let fixture = try FormFixture()
        let model = fixture.savingsModel(.create)
        model.name = "  "
        model.targetText = "1.000.000"

        #expect(!model.save())
        #expect(model.failure as? LedgerValidationError == .emptyName)
        #expect(try fixture.context.fetchCount(FetchDescriptor<SavingsGoal>()) == 0)

        model.clearFailure()
        #expect(model.failure == nil)
    }
}
