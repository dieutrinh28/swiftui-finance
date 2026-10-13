import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence

/// Each test gets its own in-memory store or temporary file; nothing touches user data.
@Suite("Persistence")
struct PersistenceTests {
    /// Keeps the container alive for the whole test; a context must not outlive its container.
    private final class Store {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            container = try ModelContainerFactory.makeContainer(at: .inMemory)
            context = ModelContext(container)
            context.autosaveEnabled = false
        }
    }

    private func makeTemporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FinanceKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: StoreLocation.defaultFileName)
    }

    @Test func schemaContainsCoreLedgerModels() {
        #expect(ModelContainerFactory.schema.entities.count == 8)
        #expect(FinanceMigrationPlan.schemas.count == 3)
        #expect(FinanceMigrationPlan.stages.count == 2)
    }

    @Test func inMemoryContainerStartsEmpty() throws {
        let store = try Store()
        let context = store.context
        #expect(try context.fetchCount(FetchDescriptor<Wallet>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LedgerTransaction>()) == 0)
    }

    @Test func seedingDefaultCategoriesIsIdempotent() throws {
        let store = try Store()
        let context = store.context

        #expect(try DefaultCategorySeeder.seedIfNeeded(in: context) == 19)
        #expect(try DefaultCategorySeeder.seedIfNeeded(in: context) == 0)

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        #expect(categories.count == 19)
        #expect(categories.filter { $0.type == .expense }.count == 13)
        #expect(categories.filter { $0.type == .income }.count == 6)
        #expect(Set(categories.compactMap(\.seedKey)).count == 19)
    }

    @Test func seedingDoesNotOverwriteUserEdits() throws {
        let store = try Store()
        let context = store.context
        try DefaultCategorySeeder.seedIfNeeded(in: context)

        let food = try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.seedKey == "expense.food" })
        food.name = "Ăn uống"
        try context.saveOrRollback()

        try DefaultCategorySeeder.seedIfNeeded(in: context)
        let names = try context.fetch(FetchDescriptor<LedgerCategory>()).map(\.name)
        #expect(names.contains("Ăn uống"))
        #expect(!names.contains("Food & Drinks"))
    }

    @Test func dataSurvivesReopeningTheStore() throws {
        let url = try makeTemporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let walletID: UUID
        do {
            let container = try ModelContainerFactory.makeContainer(at: .file(url))
            let context = ModelContext(container)
            let wallet = Wallet(
                name: "Cash", type: .cash, currency: .vnd,
                openingBalanceMinorUnits: 500_000, iconName: "banknote", colorIdentifier: "green"
            )
            context.insert(wallet)
            try context.saveOrRollback()
            walletID = wallet.id
        }

        // Simulates the next app launch: a brand-new container on the same file.
        let reopened = try ModelContainerFactory.makeContainer(at: .file(url))
        let context = ModelContext(reopened)
        let wallets = try context.fetch(FetchDescriptor<Wallet>())

        #expect(wallets.count == 1)
        let wallet = try #require(wallets.first)
        #expect(wallet.id == walletID)
        #expect(wallet.type == .cash)
        #expect(wallet.openingBalance == Money(minorUnits: 500_000, currency: .vnd))
    }

    @Test func unsavedChangesAreDiscardedOnRollback() throws {
        let store = try Store()
        let context = store.context
        context.insert(Wallet(name: "Draft", type: .cash, currency: .vnd, iconName: "banknote", colorIdentifier: "gray"))
        context.rollback()

        #expect(try context.fetchCount(FetchDescriptor<Wallet>()) == 0)
    }

    @Test func fixturesProduceAConsistentLedger() throws {
        let store = try Store()
        let context = store.context
        try PreviewFixtures.populate(context)

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        #expect(transactions.count == 4)

        // Every transfer has two legs that cancel out (same currency).
        let transfers = transactions.filter { $0.kind == .transfer }
        #expect(transfers.count == 1)
        for transfer in transfers {
            #expect(transfer.entries.count == 2)
            #expect(transfer.entries.reduce(0) { $0 + $1.amountMinorUnits } == 0)
            #expect(transfer.category == nil)
        }

        // Income and expense have exactly one leg and a category of the matching type.
        for transaction in transactions where transaction.kind != .transfer {
            #expect(transaction.entries.count == 1)
            #expect(transaction.category?.type == transaction.kind?.requiredCategoryType)
        }

        // Entry currency always matches its wallet.
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(entries.count == 5)
        for entry in entries {
            #expect(entry.currencyCode == entry.wallet?.currencyCode)
        }
    }

    @Test func fixtureCreditCardIsALiabilityWithNegativeBalance() throws {
        let store = try Store()
        let context = store.context
        try PreviewFixtures.populate(context)

        let name = PreviewFixtures.WalletName.creditCard
        let card = try #require(try context.fetch(
            FetchDescriptor<Wallet>(predicate: #Predicate { $0.name == name })
        ).first)

        #expect(card.type.accountClass == .liability)
        #expect(card.openingBalanceMinorUnits < 0)
    }

    @Test func displayAmountIsUnsigned() throws {
        let store = try Store()
        let context = store.context
        try PreviewFixtures.populate(context)

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let lunch = try #require(transactions.first { $0.note == "Lunch" })
        let atm = try #require(transactions.first { $0.kind == .transfer })

        #expect(lunch.displayAmount == Money(minorUnits: 65_000, currency: .vnd))
        #expect(atm.displayAmount == Money(minorUnits: 2_000_000, currency: .vnd))
    }

    @Test func dayKeyIsStoredInLocalTime() throws {
        let store = try Store()
        let context = store.context
        try PreviewFixtures.populate(context)

        let salary = try #require(try context.fetch(FetchDescriptor<LedgerTransaction>()).first { $0.kind == .income })
        // Reference date is Mon 12 Oct 2026 09:00 +07; salary is three days earlier.
        #expect(salary.day == DayKey(year: 2026, month: 10, day: 9))
    }
}
