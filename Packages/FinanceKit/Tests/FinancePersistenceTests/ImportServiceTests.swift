import Foundation
import SwiftData
import Testing
import FinanceDomain
@testable import FinancePersistence

@MainActor
@Suite("CSV import")
struct ImportServiceTests {
    static let header = ExportService.transactionColumns.joined(separator: ",")

    private func parse(_ lines: [String]) throws -> ParsedImport {
        try TransactionCSVParser(policy: PreviewFixtures.calendarPolicy)
            .parse(Data(([Self.header] + lines).joined(separator: "\r\n").utf8))
    }

    private func importer(_ ledger: Ledger) -> ImportService {
        ImportService(context: ledger.context, calendar: PreviewFixtures.calendarPolicy, now: { Ledger.clock })
    }

    private func populatedStore() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainerFactory.makeContainer(at: .inMemory)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try PreviewFixtures.populate(context)
        return (container, context)
    }

    @Test func exportThenImportIntoAnotherStore() throws {
        let (sourceContainer, source) = try populatedStore()
        _ = sourceContainer
        let csv = try ExportService(context: source, calendar: PreviewFixtures.calendarPolicy).transactionsCSV().render()
        let count = try source.fetchCount(FetchDescriptor<LedgerTransaction>())

        let target = try Ledger()
        let parsed = try TransactionCSVParser(policy: PreviewFixtures.calendarPolicy).parse(Data(csv.utf8))
        #expect(parsed.issues.isEmpty)
        let plan = try importer(target).plan(parsed)
        #expect(plan.ready.count == count)
        #expect(plan.issues.isEmpty)
        // Wallets used by the exported transactions (the USD wallet has none).
        #expect(plan.newWallets.count == 3)
        #expect(plan.newWallets.allSatisfy { $0.currency == .vnd })
        #expect(plan.newCategories.isEmpty)                         // default categories match by name

        let result = try importer(target).commit(plan)
        #expect(result.imported == count)
        #expect(result.newWallets == 3)
        #expect(try target.context.fetchCount(FetchDescriptor<LedgerTransaction>()) == count)

        // Same ids, kinds and amounts as the source.
        for original in try source.fetch(FetchDescriptor<LedgerTransaction>()) {
            let id = original.id
            let copy = try #require(try target.context.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.id == id })).first)
            #expect(copy.kind == original.kind)
            #expect(copy.displayAmount == original.displayAmount)
            #expect(copy.dayKey == original.dayKey)
            #expect(copy.category?.seedKey == original.category?.seedKey)
        }
    }

    /// A file exported while the app was in English imports into a store whose
    /// built-in categories are in Vietnamese, without creating duplicates.
    @Test func builtInCategoriesMatchAcrossLanguages() throws {
        let ledger = try Ledger()
        try DefaultCategorySeeder.localizeUntouched(in: ledger.context, to: .vietnamese)
        try ledger.makeWallet("Cash", opening: 0)

        let parsed = try parse([
            "2026-10-10 10:00,Expense,Cash,Food & Drinks,-65000,VND,,,,,,",
            "2026-10-10 11:00,Income,Cash,Salary,25000000,VND,,,,,,",
            "2026-10-10 12:00,Expense,Cash,Food & Drinks / Coffee,-30000,VND,,,,,,",
        ])
        let plan = try importer(ledger).plan(parsed)
        #expect(plan.issues.isEmpty)
        #expect(plan.newCategories.map(\.path) == ["Food & Drinks / Coffee"])   // only the new child

        try importer(ledger).commit(plan)
        let transactions = try ledger.context.fetch(FetchDescriptor<LedgerTransaction>())
        let food = try ledger.category("expense.food")
        #expect(food.name == "Ăn uống")
        #expect(transactions.filter { $0.category?.id == food.id }.count == 1)
        #expect(transactions.contains { $0.category?.seedKey == "income.salary" })
        #expect(transactions.contains { $0.category?.parent?.id == food.id && $0.category?.name == "Coffee" })
        #expect(try ledger.context.fetch(FetchDescriptor<LedgerCategory>()).filter { $0.parent == nil && $0.type == .expense }.count
                == DefaultCategorySeeder.expenseCategories.count)
    }

    @Test func importingTheSameFileTwiceAddsNothing() throws {
        let (container, context) = try populatedStore()
        _ = container
        let csv = try ExportService(context: context).transactionsCSV().render()
        let parsed = try TransactionCSVParser(policy: PreviewFixtures.calendarPolicy).parse(Data(csv.utf8))

        let plan = try ImportService(context: context, calendar: PreviewFixtures.calendarPolicy).plan(parsed)
        #expect(plan.ready.isEmpty)
        #expect(plan.alreadyImported == parsed.rows.count)
    }

    @Test func possibleDuplicatesAreSkippedUnlessChosen() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet("Cash", opening: 1_000_000)
        let food = try ledger.category("expense.food")
        try ledger.record(.expense, 65_000, in: cash, category: "expense.food")

        let parsed = try parse(["2026-10-12 15:00,Expense,cash,\(food.name),-65000,VND,,,,Lunch again,,"])
        let plan = try importer(ledger).plan(parsed)
        #expect(plan.ready.isEmpty)
        #expect(plan.possibleDuplicates.count == 1)

        #expect(try importer(ledger).commit(plan).imported == 0)
        #expect(try importer(ledger).commit(plan, includePossibleDuplicates: true).imported == 1)
        #expect(try cash.currentBalance() == Money(minorUnits: 870_000, currency: .vnd))
    }

    @Test func missingWalletsAndCategoriesAreCreated() throws {
        let ledger = try Ledger()
        let parsed = try parse([
            "2026-10-10 10:00,Expense,Ví MoMo,Hobbies / Lego,-450000,VND,,,,,,",
            "2026-10-10 11:00,Expense,vi momo,Hobbies,-50000,VND,,,,,,",
            "2026-10-10 12:00,Transfer,Ví MoMo,,-100000,VND,Savings box,,,,,",
        ])
        let plan = try importer(ledger).plan(parsed)
        #expect(plan.issues.isEmpty)
        #expect(plan.newWallets.map(\.name) == ["Ví MoMo", "Savings box"])          // "vi momo" is the same wallet
        #expect(plan.newCategories.map(\.path) == ["Hobbies / Lego", "Hobbies"])

        let result = try importer(ledger).commit(plan)
        #expect(result.imported == 3)
        #expect(result.newWallets == 2)
        #expect(result.newCategories == 2)                                        // Hobbies once, Lego under it

        let categories = try ledger.context.fetch(FetchDescriptor<LedgerCategory>())
        let lego = try #require(categories.first { $0.name == "Lego" })
        #expect(lego.parent?.name == "Hobbies")
        #expect(lego.type == .expense)

        let momo = try #require(try ledger.context.fetch(FetchDescriptor<Wallet>()).first { $0.name == "Ví MoMo" })
        #expect(momo.type == .other)
        #expect(try momo.currentBalance() == Money(minorUnits: -600_000, currency: .vnd))
    }

    @Test func rowsThatBreakRulesAreListed() throws {
        let ledger = try Ledger()
        let old = try ledger.makeWallet("Old", opening: 0)
        try ledger.wallets.archive(old)
        try ledger.makeWallet("Cash", opening: 0)
        let salary = try ledger.category("income.salary")

        let parsed = try parse([
            "2026-10-10 10:00,Expense,Old,Food,-1000,VND,,,,,,",
            "2026-10-10 10:00,Expense,Cash,Food,-12.50,USD,,,,,,",
            "2026-10-10 10:00,Income,Cash,\(salary.name),5000000,VND,,,,,,",
        ])
        let plan = try importer(ledger).plan(parsed)
        #expect(plan.issues.map(\.problem) == [
            .archivedWallet("Old"),
            .walletCurrencyMismatch(wallet: "Cash", currency: "USD"),
        ])
        #expect(plan.issues.map(\.line) == [2, 3])
        #expect(plan.ready.count == 1)
        #expect(plan.newWallets.isEmpty)
    }

    @Test func failedCommitKeepsNothing() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet("Cash", opening: 0)
        let parsed = try parse([
            "2026-10-10 10:00,Expense,Cash,New category,-1000,VND,,,,,,",
            "2026-10-10 11:00,Expense,Cash,Food,-2000,VND,,,,,,",
        ])
        let plan = try importer(ledger).plan(parsed)
        #expect(plan.ready.count == 2)

        // The wallet is archived between preview and confirm: the second row is rejected at commit.
        try ledger.wallets.archive(cash)
        #expect(throws: (any Error).self) { try importer(ledger).commit(plan) }
        #expect(try ledger.context.fetchCount(FetchDescriptor<LedgerTransaction>()) == 0)
        #expect(try ledger.context.fetch(FetchDescriptor<LedgerCategory>()).allSatisfy { $0.name != "New category" })
    }
}
