import Foundation
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

@MainActor
@Suite("Import flow")
struct ImportFlowModelTests {
    private struct Broken: Error {}

    private static func row(_ line: Int) -> ImportedTransaction {
        ImportedTransaction(line: line, id: nil, date: .now, kind: .expense, walletName: "Cash",
                            amount: Money(minorUnits: 1_000, currency: .vnd), categoryPath: "Food",
                            destinationName: nil, received: nil, note: nil, merchant: nil)
    }

    private static func plan(ready: Int, duplicates: Int) -> ImportPlan {
        var plan = ImportPlan()
        plan.ready = (0..<ready).map { row($0 + 2) }
        plan.possibleDuplicates = (0..<duplicates).map { row($0 + 100) }
        return plan
    }

    private final class Spy {
        var calls: [String] = []
        var committedWithDuplicates: Bool?
    }

    private func makeModel(_ spy: Spy, plan: ImportPlan, planFails: Bool = false) -> ImportFlowModel {
        ImportFlowModel(
            makePlan: { _ in
                spy.calls.append("plan")
                if planFails { throw ImportFileError.missingColumns(["Type"]) }
                return plan
            },
            commit: { plan, includeDuplicates in
                spy.calls.append("commit")
                spy.committedWithDuplicates = includeDuplicates
                return ImportResult(imported: plan.ready.count + (includeDuplicates ? plan.possibleDuplicates.count : 0),
                                    newWallets: 0, newCategories: 0)
            },
            makeSafetyCopy: {
                spy.calls.append("safetyCopy")
                return "Before import.json"
            }
        )
    }

    @Test func reviewThenConfirm() {
        let spy = Spy()
        let model = makeModel(spy, plan: Self.plan(ready: 3, duplicates: 2))
        model.load(Data())
        #expect(model.importCount == 3)
        #expect(model.canConfirm)

        model.includePossibleDuplicates = true
        #expect(model.importCount == 5)
        model.confirm()

        #expect(spy.calls == ["plan", "safetyCopy", "commit"])
        #expect(spy.committedWithDuplicates == true)
        #expect(model.step == .finished(ImportResult(imported: 5, newWallets: 0, newCategories: 0), safetyCopy: "Before import.json"))
    }

    @Test func nothingToImportCannotBeConfirmed() {
        let spy = Spy()
        let model = makeModel(spy, plan: Self.plan(ready: 0, duplicates: 1))
        model.load(Data())
        #expect(!model.canConfirm)
        model.confirm()
        #expect(spy.calls == ["plan"])

        model.includePossibleDuplicates = true
        #expect(model.canConfirm)
    }

    @Test func unreadableFileFails() {
        let spy = Spy()
        let model = makeModel(spy, plan: ImportPlan(), planFails: true)
        model.load(Data())
        #expect(model.step == .failed(message: ImportFileError.missingColumns(["Type"]).errorDescription ?? ""))
        #expect(model.isInProgress)
        model.cancel()
        #expect(!model.isInProgress)
    }

    @Test func loadingAgainResetsTheDuplicateChoice() {
        let spy = Spy()
        let model = makeModel(spy, plan: Self.plan(ready: 1, duplicates: 1))
        model.load(Data())
        model.includePossibleDuplicates = true
        model.load(Data())
        #expect(!model.includePossibleDuplicates)
    }
}
