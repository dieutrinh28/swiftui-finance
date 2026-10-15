import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }
private func usd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .usd) }

@Suite("Transfers")
struct TransferServiceTests {
    @Test func sameCurrencyTransferPreservesTotalAndIsNotCashFlow() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 10_000_000)
        let cash = try ledger.makeWallet("Cash", opening: 500_000)

        let transfer = try ledger.transactions.createTransfer(TransferDraft(
            source: bank, destination: cash, sent: vnd(2_000_000), date: Ledger.clock, note: "ATM"
        ))

        #expect(try bank.currentBalance() == vnd(8_000_000))
        #expect(try cash.currentBalance() == vnd(2_500_000))
        #expect(try bank.currentBalance().adding(cash.currentBalance()) == vnd(10_500_000))
        #expect(transfer.kind == .transfer)
        #expect(transfer.category == nil)
        #expect(transfer.exchangeRateText == nil)
        #expect(transfer.transferSource?.wallet?.id == bank.id)
        #expect(transfer.transferDestination?.wallet?.id == cash.id)
        #expect(try ledger.count(LedgerEntry.self) == 2)
    }

    @Test func crossCurrencyTransferNeedsReceivedAmount() throws {
        let ledger = try Ledger()
        let dollars = try ledger.makeWallet("USD", type: .savingsAccount, currency: .usd, opening: 50_000)
        let cash = try ledger.makeWallet("Cash", opening: 0)

        #expect(throws: LedgerValidationError.missingReceivedAmount) {
            try ledger.transactions.createTransfer(TransferDraft(
                source: dollars, destination: cash, sent: usd(10_000), date: Ledger.clock
            ))
        }
        #expect(try ledger.count(LedgerTransaction.self) == 0)

        let transfer = try ledger.transactions.createTransfer(TransferDraft(
            source: dollars, destination: cash, sent: usd(10_000), received: vnd(2_540_000), date: Ledger.clock
        ))
        #expect(try dollars.currentBalance() == usd(40_000))
        #expect(try cash.currentBalance() == vnd(2_540_000))
        #expect(transfer.exchangeRate == 25_400)
    }

    @Test func invalidTransfersWriteNothing() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet("Cash", opening: 100_000)
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 0)

        #expect(throws: LedgerValidationError.sameWalletTransfer) {
            try ledger.transactions.createTransfer(TransferDraft(source: cash, destination: cash, sent: vnd(1), date: Ledger.clock))
        }
        #expect(throws: LedgerValidationError.missingDestinationWallet) {
            try ledger.transactions.createTransfer(TransferDraft(source: cash, destination: nil, sent: vnd(1), date: Ledger.clock))
        }
        #expect(throws: LedgerValidationError.transferAmountsDiffer) {
            try ledger.transactions.createTransfer(TransferDraft(
                source: cash, destination: bank, sent: vnd(10), received: vnd(9), date: Ledger.clock))
        }
        try ledger.wallets.archive(bank)
        #expect(throws: LedgerValidationError.archivedWallet) {
            try ledger.transactions.createTransfer(TransferDraft(source: cash, destination: bank, sent: vnd(1), date: Ledger.clock))
        }

        #expect(try ledger.count(LedgerTransaction.self) == 0)
        #expect(try ledger.count(LedgerEntry.self) == 0)
        #expect(try cash.currentBalance() == vnd(100_000))
    }

    @Test func payingACreditCardIsATransferNotAnExpense() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 10_000_000)
        let card = try ledger.makeWallet("Visa", type: .creditCard, opening: 2_000_000)   // owed

        try ledger.transactions.createTransfer(TransferDraft(source: bank, destination: card, sent: vnd(500_000), date: Ledger.clock))

        #expect(try card.currentBalance() == vnd(-1_500_000))
        #expect(try bank.currentBalance() == vnd(9_500_000))
    }

    @Test func editingATransferUpdatesBothSides() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 10_000_000)
        let cash = try ledger.makeWallet("Cash", opening: 0)
        let wallet = try ledger.makeWallet("MoMo", type: .eWallet, opening: 0)
        let transfer = try ledger.transactions.createTransfer(TransferDraft(
            source: bank, destination: cash, sent: vnd(2_000_000), date: Ledger.clock))

        try ledger.transactions.updateTransfer(transfer, with: TransferDraft(
            source: bank, destination: wallet, sent: vnd(1_000_000), date: Ledger.clock, note: "Top up"))

        #expect(try bank.currentBalance() == vnd(9_000_000))
        #expect(try cash.currentBalance() == vnd(0))
        #expect(try wallet.currentBalance() == vnd(1_000_000))
        #expect(try ledger.count(LedgerEntry.self) == 2)
        #expect(transfer.note == "Top up")
    }

    @Test func rejectedTransferEditChangesNothing() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 1_000_000)
        let cash = try ledger.makeWallet("Cash", opening: 0)
        let transfer = try ledger.transactions.createTransfer(TransferDraft(
            source: bank, destination: cash, sent: vnd(200_000), date: Ledger.clock))

        #expect(throws: LedgerValidationError.sameWalletTransfer) {
            try ledger.transactions.updateTransfer(transfer, with: TransferDraft(
                source: cash, destination: cash, sent: vnd(1), date: Ledger.clock))
        }
        #expect(try bank.currentBalance() == vnd(800_000))
        #expect(try cash.currentBalance() == vnd(200_000))
    }

    @Test func deletingATransferRestoresBothBalances() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 1_000_000)
        let cash = try ledger.makeWallet("Cash", opening: 0)
        let transfer = try ledger.transactions.createTransfer(TransferDraft(
            source: bank, destination: cash, sent: vnd(200_000), date: Ledger.clock))

        try ledger.transactions.delete(transfer)

        #expect(try bank.currentBalance() == vnd(1_000_000))
        #expect(try cash.currentBalance() == vnd(0))
        #expect(try ledger.count(LedgerEntry.self) == 0)
    }

    @Test func cashFlowEditCannotTurnIntoTransfer() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 1_000_000)
        let cash = try ledger.makeWallet("Cash", opening: 0)
        let transfer = try ledger.transactions.createTransfer(TransferDraft(
            source: bank, destination: cash, sent: vnd(1), date: Ledger.clock))

        #expect(throws: LedgerValidationError.transfersNotSupported) {
            try ledger.transactions.update(transfer, with: CashFlowDraft(
                kind: .expense, amount: vnd(1), wallet: bank, category: try ledger.category("expense.food"), date: Ledger.clock))
        }
    }
}

@Suite("Budgets")
struct BudgetServiceTests {
    /// A monthly 4,000,000 VND food budget starting 1 October 2026 (the fixture clock is 12 October).
    @discardableResult
    private func foodBudget(_ ledger: Ledger, wallets: [Wallet] = [], rollover: Bool = false, start: Date? = nil) throws -> Budget {
        try ledger.budgets.create(BudgetDraft(
            name: "Food",
            plannedAmount: vnd(4_000_000),
            period: .monthly,
            startDate: start ?? PreviewFixtures.calendarPolicy.calendar.dateInterval(of: .month, for: Ledger.clock)!.start,
            categories: [try ledger.category("expense.food")],
            wallets: wallets,
            rolloverEnabled: rollover
        ))
    }

    @Test func noArtificialBudgetLimit() throws {
        let ledger = try Ledger()
        for _ in 0..<100 { try foodBudget(ledger) }
        #expect(try ledger.count(Budget.self) == 100)
    }

    @Test func utilizationFollowsTransactionChanges() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 10_000_000)
        let budget = try foodBudget(ledger)

        let lunch = try ledger.record(.expense, 2_500_000, in: cash, category: "expense.food")
        var progress = try ledger.budgets.progress(for: budget, at: Ledger.clock)
        #expect(progress.spent == vnd(2_500_000))
        #expect(progress.remaining == vnd(1_500_000))
        #expect(progress.utilization == Decimal(string: "0.625"))

        try ledger.transactions.update(lunch, with: CashFlowDraft(
            kind: .expense, amount: vnd(3_500_000), wallet: cash, category: lunch.category, date: lunch.date))
        progress = try ledger.budgets.progress(for: budget, at: Ledger.clock)
        #expect(progress.spent == vnd(3_500_000))
        #expect(progress.status == .nearLimit)

        try ledger.transactions.delete(lunch)
        progress = try ledger.budgets.progress(for: budget, at: Ledger.clock)
        #expect(progress.spent == vnd(0))
    }

    @Test func incomeTransfersAndOtherCategoriesNeverCount() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 10_000_000)
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 0)
        let budget = try foodBudget(ledger)

        try ledger.record(.income, 5_000_000, in: cash, category: "income.salary")
        try ledger.record(.expense, 300_000, in: cash, category: "expense.transportation")
        try ledger.transactions.createTransfer(TransferDraft(source: cash, destination: bank, sent: vnd(1_000_000), date: Ledger.clock))
        try ledger.record(.expense, 100_000, in: cash, category: "expense.food")

        let progress = try ledger.budgets.progress(for: budget, at: Ledger.clock)
        #expect(progress.spent == vnd(100_000))
        #expect(try ledger.budgets.spending(for: budget, in: progress.window).count == 1)
    }

    @Test func expensesOutsideThePeriodDoNotCount() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 10_000_000)
        let budget = try foodBudget(ledger)
        let calendar = PreviewFixtures.calendarPolicy.calendar
        let september = calendar.date(byAdding: .month, value: -1, to: Ledger.clock)!

        try ledger.record(.expense, 999_000, in: cash, category: "expense.food", date: september)
        try ledger.record(.expense, 1_000, in: cash, category: "expense.food")

        #expect(try ledger.budgets.progress(for: budget, at: Ledger.clock).spent == vnd(1_000))
    }

    @Test func overlappingBudgetsMeasureIndependently() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 10_000_000)
        let food = try foodBudget(ledger)
        let everyday = try ledger.budgets.create(BudgetDraft(
            name: "Everyday",
            plannedAmount: vnd(6_000_000),
            period: .monthly,
            startDate: food.startDate,
            categories: [try ledger.category("expense.food"), try ledger.category("expense.transportation")]
        ))

        try ledger.record(.expense, 200_000, in: cash, category: "expense.food")
        try ledger.record(.expense, 50_000, in: cash, category: "expense.transportation")

        #expect(try ledger.budgets.progress(for: food, at: Ledger.clock).spent == vnd(200_000))
        #expect(try ledger.budgets.progress(for: everyday, at: Ledger.clock).spent == vnd(250_000))
    }

    @Test func walletRestrictionIsRespected() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet("Cash", opening: 10_000_000)
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 10_000_000)
        let budget = try foodBudget(ledger, wallets: [cash])

        try ledger.record(.expense, 100_000, in: cash, category: "expense.food")
        try ledger.record(.expense, 900_000, in: bank, category: "expense.food")

        #expect(try ledger.budgets.progress(for: budget, at: Ledger.clock).spent == vnd(100_000))
    }

    @Test func childCategoriesAreIncluded() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 10_000_000)
        let coffee = try ledger.categories.create(CategoryDraft(
            name: "Coffee", type: .expense, iconName: "cup.and.saucer", colorIdentifier: "brown"))
        coffee.parent = try ledger.category("expense.food")
        try ledger.context.saveOrRollback()
        let budget = try foodBudget(ledger)

        try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(45_000), wallet: cash, category: coffee, date: Ledger.clock))

        #expect(try ledger.budgets.progress(for: budget, at: Ledger.clock).spent == vnd(45_000))
    }

    @Test func rolloverUsesPreviousMonth() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 10_000_000)
        let calendar = PreviewFixtures.calendarPolicy.calendar
        let september = calendar.date(byAdding: .month, value: -1, to: Ledger.clock)!
        let septemberStart = calendar.dateInterval(of: .month, for: september)!.start
        let budget = try foodBudget(ledger, rollover: true, start: septemberStart)

        try ledger.record(.expense, 3_000_000, in: cash, category: "expense.food", date: september)

        let progress = try ledger.budgets.progress(for: budget, at: Ledger.clock)
        #expect(progress.carriedOver == vnd(1_000_000))
        #expect(progress.available == vnd(5_000_000))
    }

    @Test func invalidBudgetsAreRejected() throws {
        let ledger = try Ledger()
        let start = Ledger.clock
        let food = try ledger.category("expense.food")
        let usdWallet = try ledger.makeWallet("USD", currency: .usd)

        #expect(throws: LedgerValidationError.budgetNeedsCategories) {
            try ledger.budgets.create(BudgetDraft(name: "Empty", plannedAmount: vnd(1), period: .monthly, startDate: start, categories: []))
        }
        #expect(throws: LedgerValidationError.categoryTypeMismatch(required: .expense, actual: .income)) {
            try ledger.budgets.create(BudgetDraft(name: "Salary", plannedAmount: vnd(1), period: .monthly, startDate: start,
                                                  categories: [try ledger.category("income.salary")]))
        }
        #expect(throws: LedgerValidationError.nonPositiveAmount) {
            try ledger.budgets.create(BudgetDraft(name: "Zero", plannedAmount: vnd(0), period: .monthly, startDate: start, categories: [food]))
        }
        #expect(throws: LedgerValidationError.budgetNeedsEndDate) {
            try ledger.budgets.create(BudgetDraft(name: "Trip", plannedAmount: vnd(1), period: .custom, startDate: start, categories: [food]))
        }
        #expect(throws: LedgerValidationError.currencyMismatch(walletCurrency: "USD", amountCurrency: "VND")) {
            try ledger.budgets.create(BudgetDraft(name: "Mixed", plannedAmount: vnd(1), period: .monthly, startDate: start,
                                                  categories: [food], wallets: [usdWallet]))
        }
        #expect(try ledger.count(Budget.self) == 0)
    }

    @Test func editingABudgetDoesNotTouchTransactions() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 10_000_000)
        let budget = try foodBudget(ledger)
        let lunch = try ledger.record(.expense, 100_000, in: cash, category: "expense.food")
        let updatedAt = lunch.updatedAt

        try ledger.budgets.update(budget, with: BudgetDraft(
            name: "Groceries", plannedAmount: vnd(2_000_000), period: .weekly,
            startDate: budget.startDate, categories: [try ledger.category("expense.food")]))

        #expect(budget.name == "Groceries")
        #expect(budget.period == .weekly)
        #expect(lunch.updatedAt == updatedAt)
        #expect(try cash.currentBalance() == vnd(9_900_000))
    }

    @Test func archiveRestoreAndDelete() throws {
        let ledger = try Ledger()
        let budget = try foodBudget(ledger)

        try ledger.budgets.archive(budget)
        #expect(budget.isArchived)
        try ledger.budgets.restore(budget)
        #expect(!budget.isArchived)
        try ledger.budgets.delete(budget)
        #expect(try ledger.count(Budget.self) == 0)
    }

    @Test func budgetReferencesBlockDeletingCategoriesAndWallets() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 0)
        _ = try foodBudget(ledger, wallets: [cash])

        #expect(throws: LedgerValidationError.categoryUsedByBudget) {
            try ledger.categories.delete(try ledger.category("expense.food"))
        }
        #expect(throws: LedgerValidationError.walletUsedByBudget) {
            try ledger.wallets.delete(cash)
        }
    }
}
