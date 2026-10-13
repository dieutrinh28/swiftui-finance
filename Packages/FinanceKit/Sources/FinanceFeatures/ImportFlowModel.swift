import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// The CSV import flow:
///
///     idle ──load(file)──▶ review(plan) ──confirm──▶ finished(result)
///       ▲                     │ cancel
///       └─────────────────────┘
///     unreadable file / failed import ──▶ failed(message)
///
/// Loading reads, checks and plans the import without changing anything.
/// Confirming writes a safety copy of the current data, then imports
/// everything in one save.
@MainActor
@Observable
public final class ImportFlowModel {
    public enum Step: Equatable {
        case idle
        case review(ImportPlan)
        case finished(ImportResult, safetyCopy: String?)
        case failed(message: String)
    }

    public private(set) var step: Step = .idle
    /// Also import rows that look like transactions already in the app.
    public var includePossibleDuplicates = false

    @ObservationIgnored private let makePlan: (Data) throws -> ImportPlan
    @ObservationIgnored private let commit: (ImportPlan, Bool) throws -> ImportResult
    @ObservationIgnored private let makeSafetyCopy: () throws -> String?

    /// - Parameters:
    ///   - makePlan: parses the file and plans the import (`TransactionCSVParser` + `ImportService.plan`).
    ///   - commit: `ImportService.commit(_:includePossibleDuplicates:)`.
    ///   - makeSafetyCopy: writes the current data to a file; nil when there is nothing to protect.
    public init(
        makePlan: @escaping (Data) throws -> ImportPlan,
        commit: @escaping (ImportPlan, Bool) throws -> ImportResult,
        makeSafetyCopy: @escaping () throws -> String?
    ) {
        self.makePlan = makePlan
        self.commit = commit
        self.makeSafetyCopy = makeSafetyCopy
    }

    public func load(_ data: Data) {
        do {
            includePossibleDuplicates = false
            step = .review(try makePlan(data))
        } catch {
            fail(error)
        }
    }

    public func fail(_ error: any Error) {
        step = .failed(message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    /// Number of transactions that will be added with the current choice.
    public var importCount: Int {
        guard case .review(let plan) = step else { return 0 }
        return plan.ready.count + (includePossibleDuplicates ? plan.possibleDuplicates.count : 0)
    }

    public var canConfirm: Bool { importCount > 0 }

    public func confirm() {
        guard case .review(let plan) = step, canConfirm else { return }
        do {
            let safetyCopy = try makeSafetyCopy()
            let result = try commit(plan, includePossibleDuplicates)
            step = .finished(result, safetyCopy: safetyCopy)
        } catch {
            fail(error)
        }
    }

    public func cancel() {
        step = .idle
    }

    public var isInProgress: Bool {
        if case .idle = step { return false }
        return true
    }
}
