import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence

@Suite("Report snapshot")
struct ReportServiceTests {
    private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }

    @Test func snapshotMatchesTheLedger() throws {
        let ledger = try Ledger()
        try PreviewFixtures.populate(ledger.context)

        let snapshot = try ReportService(context: ledger.context).snapshot()
        #expect(snapshot.wallets.count == 4)
        #expect(snapshot.entries.count == 5)
        #expect(snapshot.categories.count == 19)

        // Dashboard numbers equal the wallets' own balances.
        let wallets = try ledger.context.fetch(FetchDescriptor<Wallet>())
        let balances = try ReportRules.balances(snapshot)
        for wallet in wallets {
            #expect(balances[wallet.id] == (try wallet.currentBalance()))
        }
    }

    @Test func netWorthFollowsEditsAndDeletes() throws {
        let ledger = try Ledger()
        let reports = ReportService(context: ledger.context)
        let cash = try ledger.makeWallet("Cash", opening: 1_000_000)
        let card = try ledger.makeWallet("Visa", type: .creditCard, opening: 200_000)

        #expect(try ReportRules.positions(reports.snapshot()).first?.netWorth == vnd(800_000))

        let dinner = try ledger.record(.expense, 300_000, in: card)
        var position = try #require(try ReportRules.positions(reports.snapshot()).first)
        #expect(position.liabilities == vnd(500_000))
        #expect(position.netWorth == vnd(500_000))

        try ledger.transactions.delete(dinner)
        try ledger.transactions.createTransfer(TransferDraft(source: cash, destination: card, sent: vnd(200_000), date: Ledger.clock))
        position = try #require(try ReportRules.positions(reports.snapshot()).first)
        #expect(position.assets == vnd(800_000))
        #expect(position.liabilities == vnd(0))
        #expect(position.netWorth == vnd(800_000))
    }

    @Test func archivedWalletsStayInTotals() throws {
        let ledger = try Ledger()
        let old = try ledger.makeWallet("Old", opening: 50_000)
        try ledger.record(.expense, 1_000, in: old)
        try ledger.wallets.archive(old)

        let snapshot = try ReportService(context: ledger.context).snapshot()
        #expect(try ReportRules.positions(snapshot).first?.netWorth == vnd(49_000))
        #expect(try ReportRules.archivedWalletsWithBalance(snapshot) == 1)
    }

    @Test func summaryIsSearchable() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet("Tiền mặt", opening: 100_000)
        let lunch = try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(45_000), wallet: cash,
            category: try ledger.category("expense.food"), date: Ledger.clock,
            note: "Phở bò", merchant: "Phở Thìn"
        ))

        let summary = try #require(lunch.summary)
        #expect(summary.walletIDs == [cash.id])
        #expect(summary.amount == vnd(45_000))

        var query = TransactionQuery()
        query.searchText = "pho thin tien mat"
        #expect(query.matches(summary))
    }
}
