import Foundation
import Testing
import FinanceDomain
import FinanceFeatures

@MainActor
@Suite("Restore flow")
struct RestoreFlowModelTests {
    private struct DiskFull: Error {}

    private static let exportedAt = Date(timeIntervalSince1970: 1_791_770_400)

    private static func backupData() throws -> Data {
        let wallet = BackupDocument.WalletRecord(
            id: UUID(), name: "Cash", type: "cash", currencyCode: "VND", openingBalanceMinorUnits: 0,
            iconName: "banknote", colorIdentifier: "green", note: nil, sortOrder: 0,
            createdAt: exportedAt, updatedAt: exportedAt, archivedAt: nil
        )
        return try BackupCodec.encode(BackupDocument(schemaVersion: "3.0.0", exportedAt: exportedAt, wallets: [wallet]))
    }

    /// Records what the flow did, in order.
    private final class Spy {
        var calls: [String] = []
        var safetyCopyName: String? = "Before restore.json"
        var safetyCopyFails = false
    }

    private func makeModel(_ spy: Spy) -> RestoreFlowModel {
        RestoreFlowModel(
            restore: { document in
                spy.calls.append("restore")
                return try BackupValidator.validate(document)
            },
            makeSafetyCopy: {
                spy.calls.append("safetyCopy")
                if spy.safetyCopyFails { throw DiskFull() }
                return spy.safetyCopyName
            }
        )
    }

    @Test func loadShowsSummaryWithoutChangingAnything() throws {
        let spy = Spy()
        let model = makeModel(spy)
        #expect(model.step == .idle)
        #expect(!model.isInProgress)

        model.load(try Self.backupData())
        guard case .review(let summary) = model.step else {
            Issue.record("expected review, got \(model.step)")
            return
        }
        #expect(summary.wallets == 1)
        #expect(summary.exportedAt == Self.exportedAt)
        #expect(spy.calls.isEmpty)
        #expect(model.isInProgress)
    }

    @Test func confirmWritesSafetyCopyBeforeRestoring() throws {
        let spy = Spy()
        let model = makeModel(spy)
        model.load(try Self.backupData())
        model.confirm()

        #expect(spy.calls == ["safetyCopy", "restore"])
        guard case .finished(let summary, let copy) = model.step else {
            Issue.record("expected finished, got \(model.step)")
            return
        }
        #expect(summary.wallets == 1)
        #expect(copy == "Before restore.json")

        model.confirm()                                   // nothing pending any more
        #expect(spy.calls.count == 2)
    }

    @Test func noRestoreWhenSafetyCopyFails() throws {
        let spy = Spy()
        spy.safetyCopyFails = true
        let model = makeModel(spy)
        model.load(try Self.backupData())
        model.confirm()

        #expect(spy.calls == ["safetyCopy"])
        guard case .failed = model.step else {
            Issue.record("expected failed, got \(model.step)")
            return
        }
    }

    @Test func invalidFileFailsWithAMessage() {
        let spy = Spy()
        let model = makeModel(spy)
        model.load(Data(#"{"hello":"world"}"#.utf8))
        #expect(model.step == .failed(message: BackupError.notABackup.errorDescription ?? ""))

        model.confirm()                                   // ignored outside review
        #expect(spy.calls.isEmpty)

        model.cancel()
        #expect(model.step == .idle)
    }

    @Test func cancelDropsTheLoadedBackup() throws {
        let spy = Spy()
        let model = makeModel(spy)
        model.load(try Self.backupData())
        model.cancel()
        model.confirm()
        #expect(model.step == .idle)
        #expect(spy.calls.isEmpty)
    }

    @Test func routerResetReturnsHome() {
        let router = AppRouter()
        router.open(AppScreen.reports, in: .more)
        router.receive(.due)
        router.reset()
        #expect(router.selectedTab == .home)
        #expect(router.depth(of: .more) == 0)
        #expect(router.pendingRoute == nil)
    }
}
