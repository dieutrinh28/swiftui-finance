import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

@MainActor
@Suite("Transaction form model")
struct TransactionFormModelTests {
    // MARK: Defaults

    @Test func createModeStartsAsEmptyExpense() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.bank))

        #expect(!model.isEditing)
        #expect(model.kind == .expense)
        #expect(model.wallet?.id == fixture.bank.id)
        #expect(model.category == nil)
        #expect(model.amountText.isEmpty)
        #expect(model.date == FormFixture.now)
        #expect(!model.canSave)
    }

    @Test func defaultWalletIsFirstActiveAndNeverOverridesAChoice() throws {
        let fixture = try FormFixture()

        let empty = fixture.model(.create(wallet: nil))
        empty.selectDefaultWalletIfNeeded(from: [fixture.cash, fixture.bank])
        #expect(empty.wallet?.id == fixture.cash.id)

        let preselected = fixture.model(.create(wallet: fixture.bank))
        preselected.selectDefaultWalletIfNeeded(from: [fixture.cash, fixture.bank])
        #expect(preselected.wallet?.id == fixture.bank.id)
    }

    // MARK: Derived state

    @Test func canSaveNeedsWalletPositiveAmountAndCategory() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.cash))

        model.amountText = "65.000"
        #expect(!model.canSave)                       // no category

        model.category = try fixture.category("expense.food")
        #expect(model.canSave)

        model.amountText = "0"
        #expect(!model.canSave)                       // zero

        model.amountText = "abc"
        #expect(!model.canSave)                       // unparsable

        model.amountText = "65000"
        model.wallet = nil
        #expect(!model.canSave)                       // no wallet
    }

    @Test func parsedAmountReflectsInput() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.cash))

        #expect(model.parsedAmount == nil)

        model.amountText = "65.000"
        let parsed = try #require(try model.parsedAmount?.get())
        #expect(parsed == Money(minorUnits: 65_000, currency: .vnd))

        model.amountText = "65,5"
        #expect(throws: AmountInputError.tooManyDecimalPlaces(allowed: 0)) {
            try model.parsedAmount?.get()
        }
    }

    @Test func amountFollowsTheSelectedWalletsCurrency() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.usd))
        model.category = try fixture.category("expense.food")
        model.amountText = "12,50"

        #expect(model.currency == .usd)
        #expect(model.canSave)

        model.wallet = fixture.cash                   // VND has no decimals
        #expect(model.currency == .vnd)
        #expect(!model.canSave)
    }

    @Test func switchingKindClearsCategoryOfTheWrongType() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.cash))
        model.category = try fixture.category("expense.food")

        model.kind = .expense                         // same kind: kept
        #expect(model.category != nil)

        model.kind = .income
        #expect(model.category == nil)
        #expect(model.requiredCategoryType == .income)

        model.category = try fixture.category("income.salary")
        model.kind = .income
        #expect(model.category?.seedKey == "income.salary")
    }

    // MARK: Saving

    @Test func savingCreatesTransactionAndUpdatesBalance() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.cash))
        model.amountText = "65.000"
        model.category = try fixture.category("expense.food")
        model.note = "  Lunch  "

        #expect(model.save())
        #expect(model.failure == nil)
        #expect(try fixture.transactionCount() == 1)
        #expect(try fixture.cash.currentBalance().minorUnits == 935_000)
        #expect(fixture.cash.transactionsNewestFirst.first?.note == "Lunch")
    }

    @Test func savingIncomeIncreasesBalance() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.bank))
        model.kind = .income
        model.amountText = "25.000.000"
        model.category = try fixture.category("income.salary")

        #expect(model.save())
        #expect(try fixture.bank.currentBalance().minorUnits == 30_000_000)
    }

    @Test func missingWalletIsReportedAndNothingIsWritten() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: nil))
        model.amountText = "1000"

        #expect(!model.save())
        #expect(model.failure as? TransactionFormError == .missingWallet)
        #expect(try fixture.transactionCount() == 0)
    }

    @Test func serviceRuleViolationIsReported() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.cash))
        model.amountText = "1000"

        #expect(!model.save())
        #expect(model.failure as? LedgerValidationError == .missingCategory)
        #expect(try fixture.transactionCount() == 0)
        #expect(try fixture.cash.currentBalance().minorUnits == 1_000_000)
    }

    @Test func invalidAmountIsReported() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.cash))
        model.category = try fixture.category("expense.food")
        model.amountText = ""

        #expect(!model.save())
        #expect(model.failure as? AmountInputError == .empty)
    }

    @Test func failureIsClearedByASuccessfulSaveOrExplicitly() throws {
        let fixture = try FormFixture()
        let model = fixture.model(.create(wallet: fixture.cash))
        model.amountText = "1000"

        model.save()
        #expect(model.failure != nil)
        model.clearFailure()
        #expect(model.failure == nil)

        model.save()
        model.category = try fixture.category("expense.food")
        #expect(model.save())
        #expect(model.failure == nil)
    }

    // MARK: Editing

    @Test func editModePrefillsFromTransaction() throws {
        let fixture = try FormFixture()
        let creator = fixture.model(.create(wallet: fixture.cash))
        creator.amountText = "65000"
        creator.category = try fixture.category("expense.food")
        creator.note = "Lunch"
        creator.merchant = "Phở 24"
        #expect(creator.save())
        let transaction = try #require(fixture.cash.transactionsNewestFirst.first)

        let editor = fixture.model(.edit(transaction))

        #expect(editor.isEditing)
        #expect(editor.kind == .expense)
        #expect(editor.amountText == "65000")
        #expect(editor.wallet?.id == fixture.cash.id)
        #expect(editor.category?.seedKey == "expense.food")
        #expect(editor.note == "Lunch")
        #expect(editor.merchant == "Phở 24")
        #expect(editor.date == transaction.date)
        #expect(editor.canSave)
    }

    @Test func editSaveUpdatesTheSameTransaction() throws {
        let fixture = try FormFixture()
        let creator = fixture.model(.create(wallet: fixture.cash))
        creator.amountText = "65000"
        creator.category = try fixture.category("expense.food")
        #expect(creator.save())
        let transaction = try #require(fixture.cash.transactionsNewestFirst.first)

        let editor = fixture.model(.edit(transaction))
        editor.amountText = "80000"
        editor.wallet = fixture.bank
        #expect(editor.save())

        #expect(try fixture.transactionCount() == 1)
        #expect(try fixture.cash.currentBalance().minorUnits == 1_000_000)
        #expect(try fixture.bank.currentBalance().minorUnits == 4_920_000)
    }

    @Test func rejectedEditLeavesTheTransactionUnchanged() throws {
        let fixture = try FormFixture()
        let creator = fixture.model(.create(wallet: fixture.cash))
        creator.amountText = "65000"
        creator.category = try fixture.category("expense.food")
        #expect(creator.save())
        let transaction = try #require(fixture.cash.transactionsNewestFirst.first)

        let editor = fixture.model(.edit(transaction))
        editor.kind = .income                         // clears the expense category
        editor.note = "changed"
        #expect(!editor.save())
        #expect(editor.failure as? LedgerValidationError == .missingCategory)

        #expect(transaction.kind == .expense)
        #expect(transaction.note == nil)
        #expect(try fixture.cash.currentBalance().minorUnits == 935_000)
    }
}
