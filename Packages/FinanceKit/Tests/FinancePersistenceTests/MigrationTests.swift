import CoreData
import Foundation
import SwiftData
import Testing
import FinanceDomain
@testable import FinancePersistence

/// Stores written by older app versions open with the current schema and keep
/// their data.
///
/// The old store is written through Core Data with the old version's model
/// (`NSManagedObjectModel.makeManagedObjectModel(for: SchemaVn.models)`), not
/// with SwiftData: in this process SwiftData resolves an old entity to today's
/// class and crashes (`setValue:forUndefinedKey: isIrregular`). The store file
/// is then the same as one the old app wrote: same entities, same version
/// hashes, so the migration plan has to recognise and upgrade it.
@Suite("Schema migration", .serialized)
@MainActor
struct MigrationTests {
    private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }

    private func temporaryStoreURL() throws -> (URL, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory.appending(path: StoreLocation.defaultFileName),
                { try? FileManager.default.removeItem(at: directory) })
    }

    /// A wallet (opening 1,000,000), Food and Salary, and one 65,000 lunch.
    private func writeV1Ledger(_ store: OldStore) throws -> (wallet: UUID, food: UUID) {
        let now = Ledger.clock
        let walletID = UUID(), foodID = UUID()
        let wallet = try store.insert("Wallet", [
            "id": walletID, "name": "Cash", "typeRaw": WalletType.cash.rawValue, "currencyCode": "VND",
            "openingBalanceMinorUnits": Int64(1_000_000), "iconName": "banknote", "colorIdentifier": "green",
            "sortOrder": 0, "createdAt": now, "updatedAt": now,
        ])
        let food = try store.insert("LedgerCategory", [
            "id": foodID, "name": "Food & Drinks", "typeRaw": CategoryType.expense.rawValue,
            "iconName": "fork.knife", "colorIdentifier": "orange", "seedKey": "expense.food",
            "sortOrder": 0, "createdAt": now, "updatedAt": now,
        ])
        try store.insert("LedgerCategory", [
            "id": UUID(), "name": "Salary", "typeRaw": CategoryType.income.rawValue,
            "iconName": "banknote", "colorIdentifier": "green", "seedKey": "income.salary",
            "sortOrder": 1, "createdAt": now, "updatedAt": now,
        ])
        let lunch = try store.insert("LedgerTransaction", [
            "id": UUID(), "kindRaw": TransactionKind.expense.rawValue, "date": now,
            "dayKey": PreviewFixtures.calendarPolicy.dayKey(for: now).rawValue,
            "createdAt": now, "updatedAt": now, "category": food,
        ])
        try store.insert("LedgerEntry", [
            "id": UUID(), "amountMinorUnits": Int64(-65_000), "currencyCode": "VND",
            "wallet": wallet, "transaction": lunch,
        ])
        return (walletID, foodID)
    }

    @Test func storeWrittenWithV1OpensWithTheCurrentSchema() throws {
        let (url, cleanup) = try temporaryStoreURL()
        defer { cleanup() }

        let store = try OldStore(schema: SchemaV1.self, url: url)
        _ = try writeV1Ledger(store)
        try store.close()

        let container = try ModelContainerFactory.makeContainer(at: .file(url))
        let context = ModelContext(container)
        let wallet = try #require(try context.fetch(FetchDescriptor<Wallet>()).first)
        #expect(try wallet.currentBalance() == vnd(935_000))
        let lunch = try #require(try context.fetch(FetchDescriptor<LedgerTransaction>()).first)
        #expect(lunch.isIrregular == false)                       // V4 default
        #expect(lunch.category?.isIrregular == false)

        // Entities added by later versions are usable.
        let budgets = BudgetService(context: context, calendar: PreviewFixtures.calendarPolicy)
        let budget = try budgets.create(BudgetDraft(
            name: "Food", plannedAmount: vnd(4_000_000), period: .monthly,
            startDate: PreviewFixtures.calendarPolicy.calendar.dateInterval(of: .month, for: Ledger.clock)!.start,
            categories: [try #require(lunch.category)]
        ))
        #expect(try budgets.progress(for: budget, at: Ledger.clock).spent == vnd(65_000))
    }

    @Test func storeWrittenWithV3KeepsRecurringItemsAndGainsV4Fields() throws {
        let (url, cleanup) = try temporaryStoreURL()
        defer { cleanup() }

        let now = Ledger.clock
        let recurringID = UUID()
        let store = try OldStore(schema: SchemaV3.self, url: url)
        let (walletID, foodID) = try writeV1Ledger(store)
        try store.insert("RecurringTransaction", [
            "id": recurringID, "name": "Rent", "kindRaw": TransactionKind.expense.rawValue,
            "amountMinorUnits": Int64(5_000_000), "currencyCode": "VND",
            "walletID": walletID, "categoryID": foodID,
            "frequencyRaw": RecurrenceFrequency.monthly.rawValue, "interval": 1, "startDate": now,
            "reminderEnabled": true, "reminderMinutes": 9 * 60,
            "handledOccurrenceKeys": ["handled-before-migration"],
            "sortOrder": 0, "createdAt": now, "updatedAt": now,
        ])
        try store.insert("Budget", [
            "id": UUID(), "name": "Food", "plannedAmountMinorUnits": Int64(4_000_000), "currencyCode": "VND",
            "periodRaw": BudgetPeriod.monthly.rawValue, "startDate": now,
            "categoryIDs": [foodID], "walletIDs": [UUID](), "rolloverEnabled": false,
            "alertThresholdPercents": [50, 100],
            "sortOrder": 0, "createdAt": now, "updatedAt": now,
        ])
        try store.close()

        let container = try ModelContainerFactory.makeContainer(at: .file(url))
        let context = ModelContext(container)

        let rent = try #require(try context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(rent.id == recurringID)
        #expect(rent.kind == .expense)
        #expect(rent.categoryID == foodID)                       // kept although now optional
        #expect(rent.destinationWalletID == nil)                 // new fields start empty
        #expect(rent.receivedAmountMinorUnits == nil)
        #expect(rent.handledOccurrenceKeys == ["handled-before-migration"])
        #expect(rent.reminderEnabled)

        let budget = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
        #expect(budget.alertThresholdPercents == [50, 100])
        #expect(budget.categoryIDs == [foodID])
        #expect(try #require(try context.fetch(FetchDescriptor<Wallet>()).first).currentBalance() == vnd(935_000))

        // V4 fields can be written after migration.
        let lunch = try #require(try context.fetch(FetchDescriptor<LedgerTransaction>()).first)
        lunch.isIrregular = true
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.isIrregular })).count == 1)
    }
}

/// A store of an old schema version, written through Core Data with that
/// version's model, as the old app did, but without SwiftData's classes.
/// Main-actor bound with a main-queue context, so no `perform` closures are needed.
@MainActor
private final class OldStore {
    private let coordinator: NSPersistentStoreCoordinator
    private let context: NSManagedObjectContext

    init(schema: any VersionedSchema.Type, url: URL) throws {
        let made: NSManagedObjectModel? = NSManagedObjectModel.makeManagedObjectModel(for: schema.models)
        let model = try #require(made)
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try coordinator.addPersistentStore(type: .sqlite, at: url)
        context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator
    }

    /// Inserts a plain `NSManagedObject` of `entity` with `values` (attribute or relationship names).
    @discardableResult
    func insert(_ entity: String, _ values: [String: Any]) throws -> NSManagedObject {
        let description = try #require(coordinator.managedObjectModel.entitiesByName[entity], "no entity \(entity)")
        for key in values.keys {
            try #require(description.propertiesByName[key] != nil, "\(entity) has no property \(key)")
        }
        let object = NSManagedObject(entity: description, insertInto: context)
        for (key, value) in values {
            object.setValue(value, forKey: key)
        }
        return object
    }

    /// Saves and closes the file, so the next container opens it fresh.
    func close() throws {
        try context.save()
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}
