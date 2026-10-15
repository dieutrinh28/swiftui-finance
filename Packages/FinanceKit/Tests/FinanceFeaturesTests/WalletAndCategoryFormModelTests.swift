import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }

@MainActor
@Suite("Wallet form model")
struct WalletFormModelTests {
    @Test func emptyOpeningBalanceMeansZero() throws {
        let fixture = try FormFixture()
        let model = fixture.walletModel(.create)
        #expect(!model.isEditing)
        #expect(model.type == .cash)
        #expect(model.currency == .vnd)
        #expect(!model.canSave)                       // no name

        model.name = "   "
        #expect(!model.canSave)
        model.name = "Wallet"
        #expect(model.canSave)
        #expect(try model.parsedOpening.get() == vnd(0))

        model.openingText = "abc"
        #expect(!model.canSave)
        model.openingText = "250.000"
        let saved = try #require(model.save())
        #expect(model.failure == nil)
        #expect(try saved.currentBalance() == vnd(250_000))
    }

    @Test func iconFollowsTheTypeUntilChosen() throws {
        let model = try FormFixture().walletModel(.create)
        #expect(model.iconName == WalletType.cash.defaultIconName)
        model.type = .bankAccount
        #expect(model.iconName == WalletType.bankAccount.defaultIconName)

        model.iconName = "star"
        model.type = .eWallet
        #expect(model.iconName == "star")
    }

    @Test func aCardsOpeningBalanceIsWhatIsOwed() throws {
        let fixture = try FormFixture()
        let model = fixture.walletModel(.create)
        model.name = "Card"
        model.type = .creditCard
        #expect(model.isLiability)
        model.openingText = "2.000.000"
        let card = try #require(model.save())
        #expect(try card.currentBalance() == vnd(-2_000_000))

        // Editing shows the amount owed again, as a positive number.
        let editor = fixture.walletModel(.edit(card))
        #expect(editor.isEditing)
        #expect(editor.name == "Card")
        #expect(editor.iconName == WalletType.creditCard.defaultIconName)
        #expect(try FormFixture.parser.parse(editor.openingText, currency: .vnd) == vnd(2_000_000))
    }

    @Test func theCurrencyIsLockedOnceTheWalletHasTransactions() throws {
        let fixture = try FormFixture()
        #expect(!fixture.walletModel(.edit(fixture.cash)).currencyLocked)

        try fixture.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(65_000), wallet: fixture.cash,
            category: try fixture.category("expense.food"), date: FormFixture.now))
        let editor = fixture.walletModel(.edit(fixture.cash))
        #expect(editor.currencyLocked)
        editor.currency = .usd
        #expect(editor.currency == .vnd)
    }

    @Test func aRefusedSaveKeepsTheFormOpenWithTheReason() throws {
        let fixture = try FormFixture()
        try fixture.wallets.archive(fixture.bank)
        let editor = fixture.walletModel(.edit(fixture.bank))
        editor.name = "Main bank"
        #expect(editor.save() == nil)
        #expect(editor.failure as? LedgerValidationError == .archivedWallet)
        editor.clearFailure()
        #expect(editor.failure == nil)
    }
}

@MainActor
@Suite("Category form model")
struct CategoryFormModelTests {
    @Test func changingTheTypeDropsParentAndIrregular() throws {
        let fixture = try FormFixture()
        let food = try fixture.category("expense.food")
        let model = fixture.categoryModel(.create(type: .expense))
        #expect(!model.isEditing)
        #expect(model.showsIrregular)
        #expect(!model.canSave)

        model.parent = food
        model.isIrregular = true
        #expect(model.parent?.id == food.id)

        model.type = .income
        #expect(model.parent == nil)
        #expect(!model.isIrregular)
        #expect(!model.showsIrregular)
        model.isIrregular = true                       // income can't be irregular
        #expect(!model.isIrregular)
    }

    @Test func onlyTopLevelCategoriesOfTheSameTypeCanBeParents() throws {
        let fixture = try FormFixture()
        let food = try fixture.category("expense.food")
        let salary = try fixture.category("income.salary")

        let child = fixture.categoryModel(.createChild(of: food))
        child.name = "Coffee"
        let coffee = try #require(child.save())
        #expect(coffee.parent?.id == food.id)

        let model = fixture.categoryModel(.create(type: .expense))
        model.parent = salary                          // other type
        #expect(model.parent == nil)
        model.parent = coffee                          // a sub-category
        #expect(model.parent == nil)

        let parents = model.possibleParents(from: try fixture.allCategories())
        #expect(parents.contains { $0.id == food.id })
        #expect(!parents.contains { $0.id == coffee.id })
        #expect(!parents.contains { $0.id == salary.id })

        // Never itself.
        let editor = fixture.categoryModel(.edit(food))
        #expect(!editor.possibleParents(from: try fixture.allCategories()).contains { $0.id == food.id })
    }

    @Test func aNewSubcategoryStartsLikeItsParent() throws {
        let fixture = try FormFixture()
        let food = try fixture.category("expense.food")
        let model = fixture.categoryModel(.createChild(of: food))
        #expect(model.type == .expense)
        #expect(model.parent?.id == food.id)
        #expect(model.iconName == food.iconName)
        #expect(model.colorIdentifier == food.colorIdentifier)
        #expect(model.isIrregular == food.isIrregular)
    }

    @Test func historyAndSubcategoriesLockTheType() throws {
        let fixture = try FormFixture()
        let food = try fixture.category("expense.food")
        let housing = try fixture.category("expense.housing")
        #expect(!fixture.categoryModel(.edit(housing)).typeLocked)

        try fixture.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(5_000_000), wallet: fixture.bank,
            category: housing, date: FormFixture.now))
        let housingEditor = fixture.categoryModel(.edit(housing))
        #expect(housingEditor.typeLocked)
        housingEditor.type = .income
        #expect(housingEditor.type == .expense)

        let child = fixture.categoryModel(.createChild(of: food))
        child.name = "Coffee"
        #expect(child.save() != nil)
        let foodEditor = fixture.categoryModel(.edit(food))
        #expect(foodEditor.hasSubcategories)
        #expect(foodEditor.typeLocked)
        foodEditor.parent = housing                    // a parent can't become a sub-category
        #expect(foodEditor.parent == nil)
    }

    @Test func aRefusedSaveReportsTheReason() throws {
        let fixture = try FormFixture()
        let model = fixture.categoryModel(.create(type: .expense))
        model.name = "   "
        #expect(model.save() == nil)
        #expect(model.failure != nil)
    }
}
