import Foundation
import SwiftData

public enum PersistenceError: Error, Equatable, Sendable {
    case storeUnavailable(details: String)
    case saveFailed(details: String)
}

extension PersistenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            String(localized: "The local database could not be opened.", bundle: .l10n)
        case .saveFailed:
            String(localized: "Your changes could not be saved. Nothing was changed.", bundle: .l10n)
        }
    }
}

/// Where the SwiftData store lives.
public enum StoreLocation: Sendable, Equatable {
    /// Tests, previews and UI tests. Nothing touches the user's data.
    case inMemory
    /// A SQLite file on disk.
    case file(URL)

    public static let defaultFileName = "PersonalFinance.store"

    /// `Application Support/PersonalFinance.store`. Creates the directory if needed.
    public static func defaultFileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appending(path: defaultFileName)
    }

    public var fileURL: URL? {
        if case .file(let url) = self { return url }
        return nil
    }
}

public enum ModelContainerFactory {
    /// Human-readable version of the schema the app writes.
    public static let currentSchemaVersion = "4.0.0"

    public static var schema: Schema {
        Schema(versionedSchema: SchemaV4.self)
    }

    /// Opens (or creates) the store. Never deletes or resets an existing store:
    /// if opening fails, the error is returned to the caller to show the user.
    public static func makeContainer(at location: StoreLocation) throws -> ModelContainer {
        let schema = Self.schema
        let configuration: ModelConfiguration
        switch location {
        case .inMemory:
            // A unique name keeps parallel tests isolated from each other.
            configuration = ModelConfiguration(
                UUID().uuidString,
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        case .file(let url):
            configuration = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        }

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: FinanceMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            throw PersistenceError.storeUnavailable(details: String(describing: error))
        }
    }
}

extension ModelContext {
    /// The consistency boundary for every write: all changes made since the
    /// last save are committed together, or discarded together.
    ///
    /// Contexts used for writes must have `autosaveEnabled = false`, otherwise
    /// a half-built operation could be persisted before validation finishes.
    public func saveOrRollback() throws {
        do {
            try save()
        } catch {
            rollback()
            throw PersistenceError.saveFailed(details: String(describing: error))
        }
    }
}
