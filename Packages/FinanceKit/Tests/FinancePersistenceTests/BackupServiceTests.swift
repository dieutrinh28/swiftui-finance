import Foundation
import SwiftData
import Testing
import FinanceDomain
@testable import FinancePersistence

@MainActor
@Suite("Backup, restore and CSV export")
struct BackupServiceTests {
    /// A store filled with the preview data: 4 wallets (one USD), expenses,
    /// income, a transfer, a budget, a savings goal and a recurring definition.
    private func populatedStore() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainerFactory.makeContainer(at: .inMemory)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try PreviewFixtures.populate(context)
        return (container, context)
    }

    private func emptyStore() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainerFactory.makeContainer(at: .inMemory)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try DefaultCategorySeeder.seedIfNeeded(in: context)
        return (container, context)
    }

    private func service(_ context: ModelContext) -> BackupService {
        BackupService(context: context, now: { PreviewFixtures.referenceDate })
    }

    /// Fetch order is not guaranteed for equal sort keys; compare by id.
    private func normalized(_ document: BackupDocument) -> BackupDocument {
        var copy = document
        copy.wallets.sort { $0.id.uuidString < $1.id.uuidString }
        copy.categories.sort { $0.id.uuidString < $1.id.uuidString }
        copy.transactions.sort { $0.id.uuidString < $1.id.uuidString }
        for index in copy.transactions.indices {
            copy.transactions[index].entries.sort { $0.id.uuidString < $1.id.uuidString }
        }
        copy.budgets.sort { $0.id.uuidString < $1.id.uuidString }
        copy.savingsGoals.sort { $0.id.uuidString < $1.id.uuidString }
        for index in copy.savingsGoals.indices {
            copy.savingsGoals[index].contributions.sort { $0.id.uuidString < $1.id.uuidString }
        }
        copy.recurring.sort { $0.id.uuidString < $1.id.uuidString }
        return copy
    }

    @Test func backupContainsEverything() throws {
        let (container, context) = try populatedStore()
        _ = container
        let document = try service(context).makeBackup()

        #expect(document.format == BackupDocument.formatIdentifier)
        #expect(document.schemaVersion == ModelContainerFactory.currentSchemaVersion)
        #expect(document.wallets.count == 4)
        #expect(try document.transactions.count == context.fetchCount(FetchDescriptor<LedgerTransaction>()))
        #expect(document.budgets.count == 1)
        #expect(document.savingsGoals.count == 1)
        #expect(document.savingsGoals[0].contributions.count == 1)
        #expect(document.recurring.count == 1)
        #expect(try BackupValidator.validate(document).wallets == 4)
    }

    @Test func restoreReproducesTheSameData() throws {
        let (sourceContainer, source) = try populatedStore()
        let (targetContainer, target) = try emptyStore()
        _ = (sourceContainer, targetContainer)

        let original = try service(source).makeBackup()
        // Through the file format, as a real restore would be.
        let decoded = try BackupCodec.decode(try BackupCodec.encode(original))
        let summary = try service(target).restore(decoded)
        #expect(summary.transactions == original.transactions.count)

        let again = try service(target).makeBackup()
        #expect(normalized(again) == normalized(decoded))
    }

    @Test func restoredBalancesMatch() throws {
        let (sourceContainer, source) = try populatedStore()
        let (targetContainer, target) = try emptyStore()
        _ = (sourceContainer, targetContainer)

        try service(target).restore(try service(source).makeBackup())

        for wallet in try source.fetch(FetchDescriptor<Wallet>()) {
            let id = wallet.id
            let copy = try #require(try target.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == id })).first)
            #expect(try copy.currentBalance() == wallet.currentBalance())
        }
    }

    @Test func restoreReplacesExistingData() throws {
        let ledger = try Ledger()
        try ledger.makeWallet("Old wallet", opening: 5_000)
        let (sourceContainer, source) = try populatedStore()
        _ = sourceContainer

        try BackupService(context: ledger.context).restore(try service(source).makeBackup())

        let names = try ledger.context.fetch(FetchDescriptor<Wallet>()).map(\.name)
        #expect(!names.contains("Old wallet"))
        #expect(names.count == 4)
        // Default categories of the old store were replaced, not duplicated.
        let categories = try ledger.context.fetch(FetchDescriptor<LedgerCategory>())
        #expect(Set(categories.map(\.id)).count == categories.count)
        #expect(categories.count == (try source.fetchCount(FetchDescriptor<LedgerCategory>())))
    }

    @Test func invalidBackupChangesNothing() throws {
        let ledger = try Ledger()
        let wallet = try ledger.makeWallet("Keep me", opening: 5_000)
        try ledger.record(.expense, 1_000, in: wallet)
        let (sourceContainer, source) = try populatedStore()
        _ = sourceContainer

        var broken = try service(source).makeBackup()
        let index = try #require(broken.transactions.firstIndex { $0.kind == "transfer" })
        broken.transactions[index].entries[0].amountMinorUnits -= 1

        #expect(throws: BackupError.self) { try BackupService(context: ledger.context).restore(broken) }
        let names = try ledger.context.fetch(FetchDescriptor<Wallet>()).map(\.name)
        #expect(names == ["Keep me"])
        #expect(try ledger.context.fetchCount(FetchDescriptor<LedgerTransaction>()) == 1)
        #expect(try wallet.currentBalance() == Money(minorUnits: 4_000, currency: .vnd))
    }

    @Test func detectsUserData() throws {
        let ledger = try Ledger()
        #expect(try !BackupService(context: ledger.context).hasUserData())   // default categories only
        try ledger.makeWallet()
        #expect(try BackupService(context: ledger.context).hasUserData())
    }

    @Test func csvHasOneSignedRowPerTransaction() throws {
        let (container, context) = try populatedStore()
        _ = container
        let table = try ExportService(context: context, calendar: PreviewFixtures.calendarPolicy).transactionsCSV()

        #expect(table.header == ExportService.transactionColumns)
        #expect(table.rows.count == (try context.fetchCount(FetchDescriptor<LedgerTransaction>())))

        let lunch = try #require(table.rows.first { $0[9] == .text("Lunch") })
        #expect(lunch[1] == .value("Expense"))
        #expect(lunch[4] == .value("-65000"))
        #expect(lunch[5] == .value("VND"))

        let transfer = try #require(table.rows.first { $0[1] == .value("Transfer") })
        #expect(transfer[4] != .value(""))
        #expect(transfer[6] != .text(""))                  // receiving wallet
        if case .value(let amount) = transfer[4] { #expect(amount.hasPrefix("-")) }

        let rendered = table.render()
        #expect(rendered.hasPrefix("\u{FEFF}Date,Type,Wallet"))
    }

    @Test func csvRespectsTheDateRange() throws {
        let (container, context) = try populatedStore()
        _ = container
        let end = PreviewFixtures.referenceDate.addingTimeInterval(-1 * 86_400)
        let range = try DateRange(start: end.addingTimeInterval(-365 * 86_400), end: end)
        let all = try ExportService(context: context).transactionsCSV().rows.count
        let some = try ExportService(context: context).transactionsCSV(in: range).rows.count
        #expect(some < all)
    }
}
