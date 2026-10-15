import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence

@Suite("Wallets and balances")
struct WalletBalanceTests {
    @Test func openingBalanceIsNotIncome() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 1_500_000)

        #expect(try wallet.currentBalance().minorUnits == 1_500_000)
        #expect(try ledger.count(LedgerTransaction.self) == 0)
        #expect(!wallet.hasHistory)
    }

    @Test func expenseReducesAndIncomeIncreasesBalance() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 1_500_000)

        try ledger.record(.expense, 65_000, in: wallet)
        #expect(try wallet.currentBalance().minorUnits == 1_435_000)

        try ledger.record(.income, 25_000_000, in: wallet)
        #expect(try wallet.currentBalance().minorUnits == 26_435_000)
        #expect(wallet.transactionsNewestFirst.count == 2)
    }

    @Test func balancesAreIndependentPerWallet() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet("Cash", opening: 500_000)
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 10_000_000)

        try ledger.record(.expense, 100_000, in: cash)

        #expect(try cash.currentBalance().minorUnits == 400_000)
        #expect(try bank.currentBalance().minorUnits == 10_000_000)
    }

    @Test func noArtificialWalletLimit() throws {
        let ledger = try Ledger()
        for index in 0..<250 {
            try ledger.makeWallet("Wallet \(index)")
        }
        let wallets = try ledger.context.fetch(FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(wallets.count == 250)
        #expect(wallets.map(\.sortOrder) == Array(0..<250))
    }

    @Test func usdWalletKeepsCents() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet("USD", type: .savingsAccount, currency: .usd, opening: 120_000)
        try ledger.record(.expense, 1_999, in: wallet)

        #expect(try wallet.currentBalance() == Money(minorUnits: 118_001, currency: .usd))
    }

    @Test func creditCardDebtIsNegative() throws {
        let ledger = try Ledger()
        let card = try ledger.makeWallet("Visa", type: .creditCard, opening: 2_000_000)

        #expect(card.openingBalanceMinorUnits == -2_000_000)
        try ledger.record(.expense, 500_000, in: card)
        #expect(try card.currentBalance().minorUnits == -2_500_000)
        #expect(card.type.accountClass == .liability)
    }

    @Test func currencyIsLockedOnceWalletHasHistory() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet()
        var draft = WalletDraft(
            name: "Cash", type: .cash, currency: .usd,
            enteredOpeningBalance: .zero(.usd), iconName: "banknote", colorIdentifier: "green"
        )

        // Allowed while the wallet is empty.
        try ledger.wallets.update(wallet, with: draft)
        #expect(wallet.currencyCode == "USD")

        try ledger.record(.expense, 500, in: wallet)
        draft.currency = .vnd
        draft.enteredOpeningBalance = .zero(.vnd)
        #expect(throws: LedgerValidationError.walletCurrencyLocked) {
            try ledger.wallets.update(wallet, with: draft)
        }
        #expect(wallet.currencyCode == "USD")
    }

    @Test func walletWithHistoryCanBeArchivedButNotDeleted() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 100_000)
        try ledger.record(.expense, 10_000, in: wallet)

        #expect(throws: LedgerValidationError.walletHasHistory) {
            try ledger.wallets.delete(wallet)
        }

        try ledger.wallets.archive(wallet)
        #expect(wallet.isArchived)
        #expect(try wallet.currentBalance().minorUnits == 90_000)
        #expect(try ledger.count(LedgerTransaction.self) == 1)

        try ledger.wallets.restore(wallet)
        #expect(!wallet.isArchived)
    }

    @Test func emptyWalletCanBeDeleted() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet()
        try ledger.wallets.delete(wallet)
        #expect(try ledger.count(Wallet.self) == 0)
    }

    @Test func invalidWalletIsNotSaved() throws {
        let ledger = try Ledger()
        #expect(throws: LedgerValidationError.emptyName) {
            try ledger.makeWallet("   ")
        }
        #expect(throws: LedgerValidationError.negativeAmount) {
            try ledger.makeWallet(opening: -1)
        }
        #expect(try ledger.count(Wallet.self) == 0)
    }
}

@Suite("Transactions")
struct TransactionServiceTests {
    @Test func invalidTransactionsAreRejectedAndNothingIsWritten() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 100_000)
        let food = try ledger.category("expense.food")
        let salary = try ledger.category("income.salary")

        func attempt(_ kind: TransactionKind, _ amount: Money, _ category: LedgerCategory?) throws {
            try ledger.transactions.create(CashFlowDraft(
                kind: kind, amount: amount, wallet: wallet, category: category, date: Ledger.clock
            ))
        }

        #expect(throws: LedgerValidationError.nonPositiveAmount) {
            try attempt(.expense, .zero(.vnd), food)
        }
        #expect(throws: LedgerValidationError.missingCategory) {
            try attempt(.expense, Money(minorUnits: 1, currency: .vnd), nil)
        }
        #expect(throws: LedgerValidationError.categoryTypeMismatch(required: .expense, actual: .income)) {
            try attempt(.expense, Money(minorUnits: 1, currency: .vnd), salary)
        }
        #expect(throws: LedgerValidationError.currencyMismatch(walletCurrency: "VND", amountCurrency: "USD")) {
            try attempt(.expense, Money(minorUnits: 1, currency: .usd), food)
        }
        #expect(throws: LedgerValidationError.transfersNotSupported) {
            try attempt(.transfer, Money(minorUnits: 1, currency: .vnd), nil)
        }

        #expect(try ledger.count(LedgerTransaction.self) == 0)
        #expect(try ledger.count(LedgerEntry.self) == 0)
        #expect(try wallet.currentBalance().minorUnits == 100_000)
    }

    @Test func archivedWalletAndCategoryAreRejected() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet()
        try ledger.categories.archive(try ledger.category("expense.travel"))

        #expect(throws: LedgerValidationError.archivedCategory) {
            try ledger.record(.expense, 1_000, in: wallet, category: "expense.travel")
        }

        try ledger.wallets.archive(wallet)
        #expect(throws: LedgerValidationError.archivedWallet) {
            try ledger.record(.expense, 1_000, in: wallet)
        }
        #expect(try ledger.count(LedgerTransaction.self) == 0)
    }

    @Test func editingAmountUpdatesBalance() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 1_000_000)
        let lunch = try ledger.record(.expense, 65_000, in: wallet)

        var draft = CashFlowDraft(
            kind: .expense, amount: Money(minorUnits: 80_000, currency: .vnd),
            wallet: wallet, category: lunch.category, date: lunch.date, note: "  Team lunch "
        )
        try ledger.transactions.update(lunch, with: draft)

        #expect(try wallet.currentBalance().minorUnits == 920_000)
        #expect(lunch.note == "Team lunch")
        #expect(lunch.updatedAt == Ledger.clock)

        // Switching kind flips the sign: an 80,000 refund instead of an expense.
        draft.kind = .income
        draft.category = try ledger.category("income.other")
        try ledger.transactions.update(lunch, with: draft)
        #expect(try wallet.currentBalance().minorUnits == 1_080_000)
        #expect(try ledger.count(LedgerEntry.self) == 1)
    }

    @Test func movingTransactionToAnotherWalletUpdatesBoth() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet("Cash", opening: 500_000)
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 2_000_000)
        let expense = try ledger.record(.expense, 100_000, in: cash)

        try ledger.transactions.update(expense, with: CashFlowDraft(
            kind: .expense, amount: Money(minorUnits: 100_000, currency: .vnd),
            wallet: bank, category: expense.category, date: expense.date
        ))

        #expect(try cash.currentBalance().minorUnits == 500_000)
        #expect(try bank.currentBalance().minorUnits == 1_900_000)
        #expect(expense.primaryWallet?.id == bank.id)
    }

    @Test func rejectedEditLeavesTransactionUnchanged() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 100_000)
        let expense = try ledger.record(.expense, 10_000, in: wallet)

        #expect(throws: LedgerValidationError.nonPositiveAmount) {
            try ledger.transactions.update(expense, with: CashFlowDraft(
                kind: .expense, amount: .zero(.vnd), wallet: wallet,
                category: expense.category, date: expense.date, note: "changed"
            ))
        }

        #expect(expense.note == nil)
        #expect(try wallet.currentBalance().minorUnits == 90_000)
    }

    @Test func archivedCategoryCanBeKeptWhenEditing() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 100_000)
        let expense = try ledger.record(.expense, 10_000, in: wallet, category: "expense.travel")
        let travel = try #require(expense.category)
        try ledger.categories.archive(travel)

        try ledger.transactions.update(expense, with: CashFlowDraft(
            kind: .expense, amount: Money(minorUnits: 12_000, currency: .vnd),
            wallet: wallet, category: travel, date: expense.date
        ))
        #expect(try wallet.currentBalance().minorUnits == 88_000)
    }

    @Test func deletingTransactionRestoresBalance() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 1_000_000)
        try ledger.record(.expense, 65_000, in: wallet)
        let salary = try ledger.record(.income, 5_000_000, in: wallet)

        try ledger.transactions.delete(salary)

        #expect(try wallet.currentBalance().minorUnits == 935_000)
        #expect(try ledger.count(LedgerTransaction.self) == 1)
        #expect(try ledger.count(LedgerEntry.self) == 1)
    }

    @Test func archivedWalletTransactionsAreReadOnly() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet(opening: 100_000)
        let expense = try ledger.record(.expense, 10_000, in: wallet)
        try ledger.wallets.archive(wallet)

        #expect(!expense.isEditable)
        #expect(throws: LedgerValidationError.archivedWallet) {
            try ledger.transactions.delete(expense)
        }
        #expect(try ledger.count(LedgerTransaction.self) == 1)
    }

    @Test func dayKeyFollowsCalendarPolicy() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet()
        // 00:30 on 13 Oct in Vietnam = 17:30 UTC on 12 Oct.
        let lateNight = Date(timeIntervalSince1970: 1_791_826_200)
        let expense = try ledger.record(.expense, 1_000, in: wallet, date: lateNight)

        #expect(expense.day == DayKey(year: 2026, month: 10, day: 13))
    }

    @Test func ledgerSurvivesReopeningTheStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LedgerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: StoreLocation.defaultFileName)

        do {
            let ledger = try Ledger(location: .file(url))
            let wallet = try ledger.makeWallet(opening: 1_000_000)
            try ledger.record(.expense, 65_000, in: wallet)
            try ledger.record(.income, 200_000, in: wallet)
        }

        let container = try ModelContainerFactory.makeContainer(at: .file(url))
        let reopened = ModelContext(container)
        let wallet = try #require(try reopened.fetch(FetchDescriptor<Wallet>()).first)
        #expect(try wallet.currentBalance().minorUnits == 1_135_000)
        #expect(try reopened.fetchCount(FetchDescriptor<LedgerCategory>()) == 19)
    }

    /// Saving a transaction unchanged doesn't count as an edit ("Last edited" keeps its date).
    @Test func savingUnchangedDoesNotTouchLastEdited() throws {
        let ledger = try Ledger()
        var clock = Ledger.clock
        let service = TransactionService(context: ledger.context, calendar: PreviewFixtures.calendarPolicy, now: { clock })
        let cash = try ledger.makeWallet(opening: 1_000_000)
        let bank = try ledger.makeWallet("Bank", opening: 1_000_000)
        let food = try ledger.category("expense.food")
        let draft = CashFlowDraft(kind: .expense, amount: Money(minorUnits: 50_000, currency: .vnd),
                                  wallet: cash, category: food, date: Ledger.clock, note: "Lunch")
        let lunch = try service.create(draft)

        clock = Ledger.clock.addingTimeInterval(3_600)
        try service.update(lunch, with: draft)
        #expect(lunch.updatedAt == lunch.createdAt)

        var changed = draft
        changed.note = "Team lunch"
        try service.update(lunch, with: changed)
        #expect(lunch.updatedAt == clock)

        let transfer = TransferDraft(source: cash, destination: bank, sent: Money(minorUnits: 100_000, currency: .vnd),
                                     date: Ledger.clock)
        let move = try service.createTransfer(transfer)
        try service.updateTransfer(move, with: transfer)
        #expect(move.updatedAt == move.createdAt)
    }
}

@Suite("Categories")
struct CategoryServiceTests {
    @Test func createAndRename() throws {
        let ledger = try Ledger()
        let coffee = try ledger.categories.create(CategoryDraft(
            name: " Coffee ", type: .expense, iconName: "cup.and.saucer", colorIdentifier: "brown"
        ))
        #expect(coffee.name == "Coffee")
        #expect(coffee.sortOrder == 19)

        try ledger.categories.update(coffee, with: CategoryDraft(
            name: "Cà phê", type: .expense, iconName: "cup.and.saucer", colorIdentifier: "brown"
        ))
        #expect(coffee.name == "Cà phê")
    }

    @Test func usedCategoryKeepsTypeAndCannotBeDeleted() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet()
        try ledger.record(.expense, 1_000, in: wallet, category: "expense.food")
        let food = try ledger.category("expense.food")

        #expect(throws: LedgerValidationError.categoryTypeLocked) {
            try ledger.categories.update(food, with: CategoryDraft(
                name: food.name, type: .income, iconName: food.iconName, colorIdentifier: food.colorIdentifier
            ))
        }
        #expect(throws: LedgerValidationError.categoryHasHistory) {
            try ledger.categories.delete(food)
        }
        #expect(food.type == .expense)
    }

    @Test func renamingDoesNotRewriteTransactions() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet()
        let expense = try ledger.record(.expense, 1_000, in: wallet, category: "expense.food")
        let food = try #require(expense.category)
        let updatedAt = expense.updatedAt

        try ledger.categories.update(food, with: CategoryDraft(
            name: "Ăn uống", type: .expense, iconName: food.iconName, colorIdentifier: food.colorIdentifier
        ))

        #expect(expense.category?.name == "Ăn uống")
        #expect(expense.updatedAt == updatedAt)
        #expect(food.transactionsNewestFirst.count == 1)
    }

    @Test func unusedCategoryCanBeDeleted() throws {
        let ledger = try Ledger()
        try ledger.categories.delete(try ledger.category("expense.travel"))
        #expect(try ledger.count(LedgerCategory.self) == 18)
    }
}
