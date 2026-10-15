import Foundation
import SwiftData
import Testing
import FinanceDomain
@testable import FinancePersistence

/// Built-in categories in the app's language (Milestone 7).
@MainActor
@Suite("Category localization")
struct CategoryLocalizationTests {
    private func names(_ context: ModelContext) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<LedgerCategory>())
            .compactMap { category in category.seedKey.map { ($0, category.name) } })
    }

    @Test(arguments: [
        ("vi", SeedLanguage.vietnamese), ("vi-VN", .vietnamese), ("vi_VN", .vietnamese),
        ("ja", .japanese), ("ja-JP", .japanese),
        ("en", .english), ("en-GB", .english), ("fr", .english), ("", .english),
    ])
    func languageFromLocalization(identifier: String, expected: SeedLanguage) {
        #expect(SeedLanguage(localization: identifier) == expected)
    }

    @Test func missingLocalizationIsEnglish() {
        #expect(SeedLanguage(localization: nil) == .english)
    }

    @Test func everyBuiltInHasDistinctNamesInEveryLanguage() {
        for language in SeedLanguage.allCases {
            for type in [CategoryType.expense, .income] {
                let names = DefaultCategorySeeder.all.filter { $0.type == type }.map { $0.name(in: language) }
                #expect(names.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                // Folded like the CSV importer, so a name can only ever mean one built-in category.
                #expect(Set(names.map(TransactionCSVParser.key)).count == names.count)
            }
        }
        // A name never belongs to two built-in categories, across languages.
        for type in [CategoryType.expense, .income] {
            let all = DefaultCategorySeeder.all.filter { $0.type == type }.flatMap { item in
                Set(item.allNames.map(TransactionCSVParser.key)).map { ($0, item.seedKey) }
            }
            #expect(Set(all.map(\.0)).count == all.count)
        }
    }

    @Test func seedsInTheRequestedLanguage() throws {
        let ledger = try Ledger.empty()
        try DefaultCategorySeeder.seedIfNeeded(in: ledger.context, language: .vietnamese)
        let names = try names(ledger.context)
        #expect(names["expense.food"] == "Ăn uống")
        #expect(names["income.salary"] == "Lương")
        #expect(names.count == DefaultCategorySeeder.all.count)
    }

    @Test func seedsInJapanese() throws {
        let ledger = try Ledger.empty()
        try DefaultCategorySeeder.seedIfNeeded(in: ledger.context, language: .japanese)
        let names = try names(ledger.context)
        #expect(names["expense.food"] == "食費")
        #expect(names["income.salary"] == "給与")
    }

    @Test func switchingBetweenAllLanguages() throws {
        let ledger = try Ledger()
        for language in [SeedLanguage.japanese, .vietnamese, .japanese, .english] {
            try DefaultCategorySeeder.localizeUntouched(in: ledger.context, to: language)
            #expect(try ledger.category("expense.travel").name
                    == DefaultCategorySeeder.category(seedKey: "expense.travel")?.name(in: language))
        }
    }

    @Test func untouchedCategoriesFollowTheLanguage() throws {
        let ledger = try Ledger()                       // seeded in English
        #expect(try DefaultCategorySeeder.localizeUntouched(in: ledger.context, to: .vietnamese) == DefaultCategorySeeder.all.count)
        #expect(try names(ledger.context)["expense.housing"] == "Nhà ở")

        // Back to English, and running again changes nothing.
        #expect(try DefaultCategorySeeder.localizeUntouched(in: ledger.context, to: .english) == DefaultCategorySeeder.all.count)
        #expect(try names(ledger.context)["expense.housing"] == "Housing")
        #expect(try DefaultCategorySeeder.localizeUntouched(in: ledger.context, to: .english) == 0)
    }

    @Test func renamedCategoriesAreNeverTouched() throws {
        let ledger = try Ledger()
        let food = try ledger.category("expense.food")
        try ledger.categories.update(food, with: CategoryDraft(
            name: "Ăn sáng", type: .expense, iconName: food.iconName, colorIdentifier: food.colorIdentifier
        ))
        let user = try ledger.categories.create(CategoryDraft(
            name: "Housing", type: .expense, iconName: "house", colorIdentifier: "brown"
        ))

        try DefaultCategorySeeder.localizeUntouched(in: ledger.context, to: .vietnamese)

        #expect(food.name == "Ăn sáng")                 // renamed by the user
        #expect(user.name == "Housing")                 // user-created, no seed key
        #expect(try ledger.category("expense.housing").name == "Nhà ở")
    }

    @Test func renamingKeepsReferences() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet("Cash", opening: 100_000)
        let food = try ledger.category("expense.food")
        let transaction = try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: Money(minorUnits: 65_000, currency: .vnd), wallet: cash,
            category: food, date: Ledger.clock
        ))

        try DefaultCategorySeeder.localizeUntouched(in: ledger.context, to: .vietnamese)

        #expect(transaction.category?.id == food.id)
        #expect(transaction.category?.name == "Ăn uống")
        #expect(try cash.currentBalance().minorUnits == 35_000)
    }

    @Test func builtInLookupByNameInAnyLanguage() {
        let fold = TransactionCSVParser.key
        #expect(DefaultCategorySeeder.category(named: "food & drinks", type: .expense, fold: fold)?.seedKey == "expense.food")
        #expect(DefaultCategorySeeder.category(named: "an uong", type: .expense, fold: fold)?.seedKey == "expense.food")
        #expect(DefaultCategorySeeder.category(named: "食費", type: .expense, fold: fold)?.seedKey == "expense.food")
        #expect(DefaultCategorySeeder.category(named: "Ăn uống", type: .income, fold: fold) == nil)
        #expect(DefaultCategorySeeder.category(named: "Coffee", type: .expense, fold: fold) == nil)
    }
}

extension Ledger {
    /// A store without the default categories.
    static func empty() throws -> Ledger {
        let ledger = try Ledger()
        for category in try ledger.context.fetch(FetchDescriptor<LedgerCategory>()) {
            ledger.context.delete(category)
        }
        try ledger.context.save()
        return ledger
    }
}
