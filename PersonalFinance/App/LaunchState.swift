import Foundation
import FinancePersistence

/// Launch arguments understood by the app (used by UI tests).
enum LaunchArgument {
    /// Runs against a fresh in-memory store instead of the user's data.
    static let inMemoryStore = "-UseInMemoryStore"
}

/// Result of opening the database at launch.
///
/// If the store cannot be opened, the app shows `StoreErrorView`. It never
/// deletes or recreates the store to "recover", because that would destroy
/// the user's financial history.
enum LaunchState {
    case ready(AppContainer)
    case failed(StoreFailure)

    @MainActor
    static func start(arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchState {
        let location: StoreLocation
        if arguments.contains(LaunchArgument.inMemoryStore) {
            location = .inMemory
        } else {
            do {
                location = .file(try StoreLocation.defaultFileURL())
            } catch {
                return .failed(StoreFailure(error: error, storeURL: nil))
            }
        }

        do {
            return .ready(try AppContainer(location: location))
        } catch {
            return .failed(StoreFailure(error: error, storeURL: location.fileURL))
        }
    }
}

struct StoreFailure {
    let message: String
    let technicalDetails: String
    let storeURL: URL?

    init(error: any Error, storeURL: URL?) {
        self.message = (error as? LocalizedError)?.errorDescription
            ?? String(localized: "The local database could not be opened.", bundle: .l10n)
        var details = String(describing: error)
        if let storeURL {
            details += "\nStore: \(storeURL.path(percentEncoded: false))"
        }
        self.technicalDetails = details
        self.storeURL = storeURL
    }
}
