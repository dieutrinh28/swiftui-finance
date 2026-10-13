import Foundation
import Observation
import FinanceDomain

/// The restore-from-backup flow:
///
///     idle ──load(file)──▶ review(summary) ──confirm──▶ finished
///       ▲                      │  cancel                 │
///       └──────────────────────┘                         │
///     load/confirm errors ──▶ failed(message) ──reset──▶ idle
///
/// Before anything is replaced, a safety copy of the current data is written
/// (when there is data to protect). If that copy can't be written, the
/// restore does not start.
@MainActor
@Observable
public final class RestoreFlowModel {
    public enum Step: Equatable {
        case idle
        /// The file is a valid backup; waiting for the user to confirm.
        case review(BackupSummary)
        /// Done. `safetyCopy` names the file holding the previous data, if any.
        case finished(BackupSummary, safetyCopy: String?)
        case failed(message: String)
    }

    public private(set) var step: Step = .idle

    @ObservationIgnored private var pending: BackupDocument?
    @ObservationIgnored private let restore: (BackupDocument) throws -> BackupSummary
    @ObservationIgnored private let makeSafetyCopy: () throws -> String?

    /// - Parameters:
    ///   - restore: replaces the store's data (`BackupService.restore`).
    ///   - makeSafetyCopy: writes the current data to a file and returns its
    ///     name, or nil when there is nothing to protect.
    public init(
        restore: @escaping (BackupDocument) throws -> BackupSummary,
        makeSafetyCopy: @escaping () throws -> String?
    ) {
        self.restore = restore
        self.makeSafetyCopy = makeSafetyCopy
    }

    /// Reads and validates a backup file. Nothing is changed yet.
    public func load(_ data: Data) {
        do {
            let document = try BackupCodec.decode(data)
            let summary = try BackupValidator.validate(document)
            pending = document
            step = .review(summary)
        } catch {
            pending = nil
            step = .failed(message: Self.message(for: error))
        }
    }

    /// Reports a file that could not even be opened (e.g. permission denied).
    public func fail(_ error: any Error) {
        pending = nil
        step = .failed(message: Self.message(for: error))
    }

    /// Writes the safety copy, then replaces all data with the backup.
    public func confirm() {
        guard case .review = step, let document = pending else { return }
        do {
            let safetyCopy = try makeSafetyCopy()
            let summary = try restore(document)
            pending = nil
            step = .finished(summary, safetyCopy: safetyCopy)
        } catch {
            step = .failed(message: Self.message(for: error))
        }
    }

    public func cancel() {
        pending = nil
        step = .idle
    }

    public var isInProgress: Bool {
        if case .idle = step { return false }
        return true
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
