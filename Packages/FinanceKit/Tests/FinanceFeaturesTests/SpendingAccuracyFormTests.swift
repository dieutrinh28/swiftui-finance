import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Milestone 8 form behaviour: irregular flag, alert levels, recurring transfers.
@MainActor
@Suite("Spending accuracy forms")
struct SpendingAccuracyFormTests {
    @Test func irregularFollowsTheCategoryUntilTheUserChoosesIt() throws {
        let fixture = try FormFixture()
        let travel = try fixture.category("expense.travel")
        travel.isIrregular = true
        let model = fixture.model(.create(wallet: fixture.cash))
        model.kind = .expense
        model.amountText = "500.000"

        #expect(model.offersIrregular)
        model.category = travel
        #expect(model.isIrregular)
        model.category = try fixture.category("expense.food")
        #expect(!model.isIrregular)

        model.isIrregular = true                       // chosen: kept across category changes
        model.category = travel
        model.category = try fixture.category("expense.shopping")
        #expect(model.isIrregular)
        #expect(model.save())

        let saved = try #require(try fixture.context.fetch(FetchDescriptor<LedgerTransaction>()).first)
        #expect(saved.isIrregular)
    }

    @Test func budgetAlertLevelsToggleAndSave() throws {
        let fixture = try FormFixture()
        let model = fixture.budgetModel(.create)
        #expect(model.alertThresholds == [80, 100])
        model.name = "Food"
        model.amountText = "4.000.000"
        let food = try fixture.category("expense.food")
        model.toggleCategory(food)
        model.toggleAlert(80)
        model.toggleAlert(50)
        #expect(model.alertThresholds == [50, 100])
        #expect(model.save(categories: [food], wallets: []))

        let budget = try #require(try fixture.context.fetch(FetchDescriptor<Budget>()).first)
        #expect(budget.alertThresholdPercents == [50, 100])
        #expect(fixture.budgetModel(.edit(budget)).alertThresholds == [50, 100])
    }

    @Test func recurringTransferNeedsADestinationAndNoCategory() throws {
        let fixture = try FormFixture()
        let model = fixture.recurringModel(.create)
        model.name = "Save"
        model.kind = .transfer
        model.wallet = fixture.bank
        model.amountText = "2.000.000"
        #expect(!model.canSave)                         // no destination

        model.destination = fixture.cash
        #expect(!model.needsReceivedAmount)
        #expect(model.canSave)                          // no category needed
        #expect(model.destinationChoices(from: fixture.allWallets).map(\.id) == [fixture.cash.id, fixture.usd.id])

        model.wallet = fixture.cash                     // same as the destination: cleared
        #expect(model.destination == nil)

        model.destination = fixture.usd
        #expect(model.needsReceivedAmount)
        #expect(!model.canSave)
        model.receivedText = "100"
        #expect(model.canSave)
        #expect(model.save())

        let saved = try #require(try fixture.context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(saved.kind == .transfer)
        #expect(saved.categoryID == nil)
        #expect(saved.destinationWalletID == fixture.usd.id)
        #expect(saved.receivedAmountMinorUnits == 10_000)
    }
}
