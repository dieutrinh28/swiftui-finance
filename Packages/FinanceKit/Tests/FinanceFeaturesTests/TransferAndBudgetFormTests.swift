import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }

@MainActor
@Suite("Transaction form model: transfers")
struct TransferFormModelTests {
    @Test func newTransactionOffersAllKinds() throws {
        let fixture = try FormFixture()
        #expect(fixture.model(.create(wallet: nil)).availableKinds == [.expense, .income, .transfer])
    }

    @Test func switchingToTransferClearsCategory() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.bank))
        model.category = try fixture.category("expense.food")

        model.kind = .transfer
        #expect(model.category == nil)
        #expect(model.isTransfer)
    }

    @Test func sameCurrencyTransferNeedsDifferentDestination() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.bank))
        model.kind = .transfer
        model.amountText = "2.000.000"

        #expect(!model.canSave)                       // no destination
        model.destinationWallet = fixture.bank
        #expect(!model.canSave)                       // same wallet
        model.destinationWallet = fixture.cash
        #expect(!model.needsReceivedAmount)
        #expect(model.canSave)

        #expect(model.save())
        #expect(try fixture.bank.currentBalance() == vnd(3_000_000))
        #expect(try fixture.cash.currentBalance() == vnd(3_000_000))
    }

    @Test func crossCurrencyTransferAsksForReceivedAmount() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.usd))
        model.kind = .transfer
        model.destinationWallet = fixture.cash
        model.amountText = "50"

        #expect(model.needsReceivedAmount)
        #expect(!model.canSave)

        model.receivedAmountText = "1.270.000"
        #expect(model.canSave)
        #expect(model.impliedExchangeRate == 25_400)

        #expect(model.save())
        #expect(try fixture.usd.currentBalance() == Money(minorUnits: 5_000, currency: .usd))
        #expect(try fixture.cash.currentBalance() == vnd(2_270_000))
    }

    @Test func editingATransferPrefillsAndKeepsItATransfer() throws {
        let fixture = try FormFixture()
        let creator = fixture.model(.create(wallet: fixture.bank))
        creator.kind = .transfer
        creator.destinationWallet = fixture.cash
        creator.amountText = "500000"
        creator.note = "ATM"
        #expect(creator.save())
        let transfer = try #require(fixture.cash.transactionsNewestFirst.first)

        let editor = fixture.model(.edit(transfer))
        #expect(editor.availableKinds == [.transfer])
        #expect(editor.wallet?.id == fixture.bank.id)
        #expect(editor.destinationWallet?.id == fixture.cash.id)
        #expect(editor.amountText == "500000")
        #expect(editor.note == "ATM")

        editor.amountText = "300000"
        #expect(editor.save())
        #expect(try fixture.bank.currentBalance() == vnd(4_700_000))
        #expect(try fixture.cash.currentBalance() == vnd(1_300_000))
        #expect(try fixture.transactionCount() == 1)
    }

    @Test func editingIncomeOffersOnlyIncomeAndExpense() throws {
        let fixture = try FormFixture()
        let creator = fixture.model(.create(wallet: fixture.cash))
        creator.kind = .income
        creator.amountText = "1000"
        creator.category = try fixture.category("income.gifts")
        #expect(creator.save())
        let income = try #require(fixture.cash.transactionsNewestFirst.first)

        #expect(fixture.model(.edit(income)).availableKinds == [.expense, .income])
    }

    @Test func transferFailureIsReported() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.bank))
        model.kind = .transfer
        model.amountText = "1000"

        #expect(!model.save())
        #expect(model.failure as? LedgerValidationError == .missingDestinationWallet)
        #expect(try fixture.transactionCount() == 0)
    }
}

@MainActor
@Suite("Budget form model")
struct BudgetFormModelTests {
    @Test func defaultsCoverTheCurrentMonth() throws {
        let fixture = try FormFixture()
        let model = fixture.budgetModel(.create)
        let calendar = PreviewFixtures.calendarPolicy

        #expect(!model.isEditing)
        #expect(model.period == .monthly)
        #expect(model.currency == .vnd)
        #expect(calendar.dayKey(for: model.startDate) == DayKey(year: 2026, month: 10, day: 1))
        #expect(calendar.dayKey(for: model.endDate) == DayKey(year: 2026, month: 10, day: 31))
        #expect(model.effectiveEndDate == nil)
        #expect(!model.canSave)
    }

    @Test func canSaveRules() throws {
        let fixture = try FormFixture()
        let model = fixture.budgetModel(.create)
        model.name = "Food"
        model.amountText = "4.000.000"
        #expect(!model.canSave)                         // no category

        model.toggleCategory(try fixture.category("expense.food"))
        #expect(model.canSave)

        model.limitsWallets = true
        #expect(!model.canSave)                         // limited, but no wallet chosen
        model.toggleWallet(fixture.cash)
        #expect(model.canSave)

        model.period = .custom
        #expect(model.requiresEndDate)
        #expect(!model.supportsRollover)
        model.endDate = model.startDate.addingTimeInterval(-86_400)
        #expect(!model.canSave)                         // ends before it starts
    }

    @Test func togglingTwiceDeselects() throws {
        let fixture = try FormFixture()
        let model = fixture.budgetModel(.create)
        let food = try fixture.category("expense.food")

        model.toggleCategory(food)
        model.toggleCategory(food)
        #expect(model.selectedCategoryIDs.isEmpty)
    }

    @Test func changingCurrencyClearsWalletsAndFiltersChoices() throws {
        let fixture = try FormFixture()
        let model = fixture.budgetModel(.create)
        model.limitsWallets = true
        model.toggleWallet(fixture.cash)

        #expect(model.selectableWallets(from: fixture.allWallets).map(\.name) == ["Cash", "Bank"])
        model.currency = .usd
        #expect(model.selectedWalletIDs.isEmpty)
        #expect(model.selectableWallets(from: fixture.allWallets).map(\.name) == ["USD"])
    }

    @Test func onlyExpenseCategoriesAreSelectable() throws {
        let fixture = try FormFixture()
        let model = fixture.budgetModel(.create)
        let selectable = model.selectableCategories(from: try fixture.allCategories())
        #expect(selectable.count == 13)
        #expect(selectable.allSatisfy { $0.type == .expense })
    }

    @Test func savingCreatesABudgetThatMeasuresSpending() throws {
        let fixture = try FormFixture()
        let model = fixture.budgetModel(.create)
        model.name = "Food"
        model.amountText = "4.000.000"
        model.toggleCategory(try fixture.category("expense.food"))

        #expect(model.save(categories: try fixture.allCategories(), wallets: fixture.allWallets))

        let budget = try #require(try fixture.context.fetch(FetchDescriptor<Budget>()).first)
        #expect(budget.plannedAmount == vnd(4_000_000))
        #expect(budget.appliesToAllWallets)

        try fixture.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(2_500_000), wallet: fixture.cash,
            category: try fixture.category("expense.food"), date: FormFixture.now))
        #expect(try fixture.budgets.progress(for: budget, at: FormFixture.now).utilization == Decimal(string: "0.625"))
    }

    @Test func editPrefillsAndUpdates() throws {
        let fixture = try FormFixture()
        let creator = fixture.budgetModel(.create)
        creator.name = "Food"
        creator.amountText = "4000000"
        creator.toggleCategory(try fixture.category("expense.food"))
        creator.limitsWallets = true
        creator.toggleWallet(fixture.cash)
        creator.rolloverEnabled = true
        #expect(creator.save(categories: try fixture.allCategories(), wallets: fixture.allWallets))
        let budget = try #require(try fixture.context.fetch(FetchDescriptor<Budget>()).first)

        let editor = fixture.budgetModel(.edit(budget))
        #expect(editor.isEditing)
        #expect(editor.name == "Food")
        #expect(editor.amountText == "4000000")
        #expect(editor.limitsWallets)
        #expect(editor.selectedWalletIDs == [fixture.cash.id])
        #expect(editor.rolloverEnabled)

        editor.amountText = "5000000"
        editor.limitsWallets = false
        #expect(editor.save(categories: try fixture.allCategories(), wallets: fixture.allWallets))
        #expect(budget.plannedAmount == vnd(5_000_000))
        #expect(budget.appliesToAllWallets)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Budget>()) == 1)
    }

    @Test func invalidSaveIsReported() throws {
        let fixture = try FormFixture()
        let model = fixture.budgetModel(.create)
        model.name = "Food"
        model.amountText = "4000000"

        #expect(!model.save(categories: try fixture.allCategories(), wallets: fixture.allWallets))
        #expect(model.failure as? LedgerValidationError == .budgetNeedsCategories)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Budget>()) == 0)

        model.clearFailure()
        #expect(model.failure == nil)
    }
}
