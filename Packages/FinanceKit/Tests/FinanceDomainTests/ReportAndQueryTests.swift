import Foundation
import Testing
import FinanceDomain

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }
private func usd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .usd) }
private func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

/// Cash 1,000,000 · Bank 10,000,000 · Card owing 2,000,000 · archived Old wallet 50,000 · USD 100.00
private struct Fixture {
    let cash = UUID(), bank = UUID(), card = UUID(), old = UUID(), dollars = UUID()
    let food = UUID(), rent = UUID(), salary = UUID()

    var wallets: [WalletSnapshot] {
        [
            WalletSnapshot(id: cash, name: "Cash", accountClass: .asset, openingBalance: vnd(1_000_000)),
            WalletSnapshot(id: bank, name: "Bank", accountClass: .asset, openingBalance: vnd(10_000_000)),
            WalletSnapshot(id: card, name: "Card", accountClass: .liability, openingBalance: vnd(-2_000_000)),
            WalletSnapshot(id: old, name: "Old", accountClass: .asset, openingBalance: vnd(50_000), isArchived: true),
            WalletSnapshot(id: dollars, name: "USD", accountClass: .asset, openingBalance: usd(10_000)),
        ]
    }

    func entry(_ kind: TransactionKind, _ amount: Money, _ wallet: UUID, _ d: DayKey,
               category: UUID? = nil, tx: UUID = UUID()) -> EntrySnapshot {
        EntrySnapshot(transactionID: tx, kind: kind, day: d, walletID: wallet, amount: amount, categoryID: category)
    }

    var snapshot: LedgerSnapshot {
        let transfer = UUID()
        return LedgerSnapshot(wallets: wallets, entries: [
            entry(.income, vnd(25_000_000), bank, day(2026, 10, 1), category: salary),
            entry(.expense, vnd(-6_000_000), bank, day(2026, 10, 2), category: rent),
            entry(.expense, vnd(-65_000), cash, day(2026, 10, 5), category: food),
            entry(.expense, vnd(-500_000), card, day(2026, 10, 6), category: food),
            entry(.transfer, vnd(-2_000_000), bank, day(2026, 10, 7), tx: transfer),
            entry(.transfer, vnd(2_000_000), cash, day(2026, 10, 7), tx: transfer),
            entry(.expense, vnd(-100_000), cash, day(2026, 9, 20), category: food),
            entry(.expense, usd(-1_999), dollars, day(2026, 10, 3), category: food),
        ])
    }
}

@Suite("Report rules")
struct ReportRulesTests {
    private let policy = CalendarPolicy(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)
    private let october = DayRange(first: day(2026, 10, 1), end: day(2026, 11, 1))

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func positionsSeparateAssetsLiabilitiesAndCurrencies() throws {
        let positions = try ReportRules.positions(Fixture().snapshot)

        #expect(positions.map(\.currency) == [.vnd, .usd])
        let vndPosition = try #require(positions.first)
        // Cash 1,000,000 − 65,000 − 100,000 + 2,000,000 = 2,835,000
        // Bank 10,000,000 + 25,000,000 − 6,000,000 − 2,000,000 = 27,000,000
        // Old (archived) 50,000 → assets 29,885,000
        #expect(vndPosition.assets == vnd(29_885_000))
        #expect(vndPosition.liabilities == vnd(2_500_000))
        #expect(vndPosition.netWorth == vnd(27_385_000))
        #expect(positions[1].netWorth == usd(8_001))
    }

    @Test func transfersDoNotChangeNetWorth() throws {
        let fixture = Fixture()
        let withoutTransfer = LedgerSnapshot(
            wallets: fixture.wallets,
            entries: fixture.snapshot.entries.filter { $0.kind != .transfer }
        )
        #expect(try ReportRules.positions(fixture.snapshot)[0].netWorth
                == ReportRules.positions(withoutTransfer)[0].netWorth)
    }

    @Test func positionsBeforeADayIgnoreLaterEntries() throws {
        let positions = try ReportRules.positions(Fixture().snapshot, before: day(2026, 10, 1))
        // Only opening balances and the September expense.
        #expect(positions[0].netWorth == vnd(1_000_000 + 10_000_000 - 2_000_000 + 50_000 - 100_000))
    }

    @Test func archivedWalletsWithMoneyAreReported() throws {
        #expect(try ReportRules.archivedWalletsWithBalance(Fixture().snapshot) == 1)
    }

    @Test func cashFlowExcludesTransfersAndOtherPeriods() throws {
        let flow = try ReportRules.cashFlow(Fixture().snapshot, in: october)

        let vndFlow = try #require(flow.first { $0.currency == .vnd })
        #expect(vndFlow.income == vnd(25_000_000))
        #expect(vndFlow.expenses == vnd(6_565_000))
        #expect(vndFlow.net == vnd(18_435_000))

        let usdFlow = try #require(flow.first { $0.currency == .usd })
        #expect(usdFlow.expenses == usd(1_999))
        #expect(usdFlow.income == usd(0))
    }

    @Test func emptyLedgerGivesZeroesNotErrors() throws {
        let snapshot = LedgerSnapshot(wallets: [
            WalletSnapshot(id: UUID(), name: "Cash", accountClass: .asset, openingBalance: vnd(0)),
        ])
        let flow = try ReportRules.cashFlow(snapshot, in: october, currency: .vnd)
        #expect(flow.income == vnd(0) && flow.expenses == vnd(0))
        #expect(try ReportRules.expensesByCategory(snapshot, in: october, currency: .vnd).isEmpty)
        #expect(try ReportRules.positions(LedgerSnapshot.empty).isEmpty)
    }

    @Test func expensesByCategoryWithShares() throws {
        let fixture = Fixture()
        let shares = try ReportRules.expensesByCategory(fixture.snapshot, in: october, currency: .vnd)

        #expect(shares.map(\.key) == [.category(fixture.rent), .category(fixture.food)])
        #expect(shares[0].amount == vnd(6_000_000))
        #expect(shares[1].amount == vnd(565_000))
        let total = shares.reduce(Decimal(0)) { $0 + $1.share }
        #expect(abs(total - 1) < Decimal(string: "0.000001")!)
    }

    @Test func expensesByWallet() throws {
        let fixture = Fixture()
        let shares = try ReportRules.expensesByWallet(fixture.snapshot, in: october, currency: .vnd)
        #expect(shares.map(\.key) == [.wallet(fixture.bank), .wallet(fixture.card), .wallet(fixture.cash)])
    }

    @Test func topFoldsTheRestIntoOther() throws {
        // Explicit types: the inferred version is too slow for the type checker.
        let shares: [AmountShare] = (1...5).map { (index: Int) -> AmountShare in
            let weight = 6 - index
            return AmountShare(key: .category(UUID()), amount: vnd(Int64(100 * weight)),
                               share: Decimal(weight) / Decimal(15))
        }
        let folded = try ReportRules.top(shares, limit: 3)

        #expect(folded.count == 4)
        #expect(folded.last?.key == .other)
        #expect(folded.last?.amount == vnd(300))           // 200 + 100
        let otherShare = try #require(folded.last?.share)
        #expect(abs(otherShare - Decimal(3) / 15) < Decimal(string: "0.000001")!)
        #expect(try ReportRules.top(shares, limit: 10).count == 5)
    }

    @Test func monthRangesEndWithTheCurrentMonth() throws {
        let months = try policy.monthRanges(endingWith: date("2026-01-15T10:00:00+07:00"), count: 3)
        #expect(months.map { policy.dayKey(for: $0.start) } == [day(2025, 11, 1), day(2025, 12, 1), day(2026, 1, 1)])
        #expect(policy.dayKey(for: months[2].end) == day(2026, 2, 1))
    }

    @Test func cashFlowTrendPerMonth() throws {
        let months = try policy.monthRanges(endingWith: date("2026-10-12T09:00:00+07:00"), count: 2)
        let trend = try ReportRules.cashFlowTrend(Fixture().snapshot, periods: months, currency: .vnd, policy: policy)

        #expect(trend.count == 2)
        #expect(trend[0].expenses == vnd(100_000))           // September
        #expect(trend[0].income == vnd(0))
        #expect(trend[1].income == vnd(25_000_000))          // October
        #expect(trend[1].net == vnd(18_435_000))
    }

    @Test func netWorthTrendClosesEachMonth() throws {
        let months = try policy.monthRanges(endingWith: date("2026-10-12T09:00:00+07:00"), count: 2)
        let trend = try ReportRules.netWorthTrend(Fixture().snapshot, periods: months, currency: .vnd, policy: policy)

        #expect(trend[0].netWorth == vnd(8_950_000))         // end of September
        #expect(trend[1].netWorth == vnd(27_385_000))        // end of October = today's position
    }

    @Test func dailyExpensesRunningTotal() throws {
        let range = try DateRange(start: date("2026-10-01T00:00:00+07:00"), end: date("2026-10-08T00:00:00+07:00"))
        let days = try ReportRules.dailyExpenses(Fixture().snapshot, in: range, currency: .vnd, policy: policy)

        #expect(days.count == 7)
        #expect(days[1].amount == vnd(6_000_000))            // 2 October
        #expect(days[4].amount == vnd(65_000))               // 5 October
        #expect(days.last?.cumulative == vnd(6_565_000))
    }

    @Test func currencyOrderPutsDefaultFirst() {
        #expect(ReportRules.ordered([.usd, .eur, .vnd]) == [.vnd, .eur, .usd])
    }
}

@Suite("Transaction query")
struct TransactionQueryTests {
    private let cash = UUID(), bank = UUID(), food = UUID(), rent = UUID()

    private func summary(
        _ kind: TransactionKind = .expense, _ minor: Int64, wallets: Set<UUID>, category: UUID? = nil,
        day d: Int, text: String = ""
    ) -> TransactionSummary {
        TransactionSummary(
            id: UUID(), kind: kind,
            date: Date(timeIntervalSince1970: TimeInterval(1_790_000_000 + d * 86_400)),
            day: day(2026, 10, d), amount: vnd(minor), walletIDs: wallets, categoryID: category,
            searchableText: text
        )
    }

    private var items: [TransactionSummary] {
        [
            summary(.expense, 65_000, wallets: [cash], category: food, day: 5, text: "Phở bò · Food & Drinks · Cash"),
            summary(.expense, 6_000_000, wallets: [bank], category: rent, day: 2, text: "Tiền nhà · Housing · Bank"),
            summary(.income, 25_000_000, wallets: [bank], day: 1, text: "Lương tháng 10 · Salary · Bank"),
            summary(.transfer, 2_000_000, wallets: [bank, cash], day: 7, text: "Rút tiền · Bank → Cash"),
            summary(.expense, 30_000, wallets: [cash], category: food, day: 9, text: "Đá chanh · Food & Drinks · Cash"),
        ]
    }

    @Test func emptyQueryReturnsEverythingNewestFirst() {
        let query = TransactionQuery()
        #expect(!query.isFiltering)
        #expect(query.apply(to: items).map(\.day.day) == [9, 7, 5, 2, 1])
    }

    @Test func searchIgnoresCaseAndVietnameseAccents() {
        var query = TransactionQuery()
        query.searchText = "pho"
        #expect(query.apply(to: items).count == 1)

        query.searchText = "da chanh"
        #expect(query.apply(to: items).map(\.amount) == [vnd(30_000)])

        query.searchText = "LUONG"
        #expect(query.apply(to: items).first?.kind == .income)

        query.searchText = "food cash"           // every word must match
        #expect(query.apply(to: items).count == 2)
        #expect(query.isFiltering)
    }

    @Test func filtersCombine() {
        var query = TransactionQuery()
        query.kinds = [.expense]
        #expect(query.apply(to: items).count == 3)

        query.categoryIDs = [food]
        #expect(query.apply(to: items).count == 2)

        query.minimumAmount = 50_000
        #expect(query.apply(to: items).map(\.amount) == [vnd(65_000)])
        #expect(query.activeFilterCount == 3)
    }

    @Test func walletFilterMatchesEitherSideOfATransfer() {
        var query = TransactionQuery()
        query.walletIDs = [cash]
        #expect(query.apply(to: items).map(\.kind) == [.expense, .transfer, .expense])
    }

    @Test func dateRangeAndAmountBoundsAreInclusive() {
        var query = TransactionQuery()
        query.dayRange = DayRange(first: day(2026, 10, 2), end: day(2026, 10, 6))
        #expect(query.apply(to: items).map(\.day.day) == [5, 2])

        query = TransactionQuery()
        query.minimumAmount = 30_000
        query.maximumAmount = 65_000
        #expect(query.apply(to: items).count == 2)
    }

    @Test func sortOrders() {
        var query = TransactionQuery()
        query.sort = .largestFirst
        #expect(query.apply(to: items).first?.amount == vnd(25_000_000))
        query.sort = .smallestFirst
        #expect(query.apply(to: items).first?.amount == vnd(30_000))
        query.sort = .oldestFirst
        #expect(query.apply(to: items).first?.day.day == 1)
    }

    @Test func largeHistoryIsHandled() {
        let many = (0..<10_000).map { index in
            summary(.expense, Int64(1_000 + index), wallets: [cash], category: food, day: 1 + index % 28, text: "item \(index)")
        }
        var query = TransactionQuery()
        query.searchText = "item 9999"
        #expect(query.apply(to: many).count == 1)
        query.searchText = ""
        query.sort = .largestFirst
        #expect(query.apply(to: many).first?.amount == vnd(10_999))
    }
}
