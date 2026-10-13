import Foundation
import Testing
import FinanceDomain

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }
private func usd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .usd) }

@Suite("Transfer rules")
struct TransferRulesTests {
    @Test func sameCurrencyTransferMustPreserveTheAmount() throws {
        try LedgerRules.validateTransfer(TransferCandidate(
            sent: vnd(2_000_000), received: vnd(2_000_000), sourceCurrency: .vnd, destinationCurrency: .vnd
        ))
        #expect(throws: LedgerValidationError.transferAmountsDiffer) {
            try LedgerRules.validateTransfer(TransferCandidate(
                sent: vnd(2_000_000), received: vnd(1_999_000), sourceCurrency: .vnd, destinationCurrency: .vnd
            ))
        }
    }

    @Test func crossCurrencyTransferUsesExplicitAmounts() throws {
        try LedgerRules.validateTransfer(TransferCandidate(
            sent: usd(10_000), received: vnd(2_540_000), sourceCurrency: .usd, destinationCurrency: .vnd
        ))
        #expect(LedgerRules.impliedExchangeRate(sent: usd(10_000), received: vnd(2_540_000)) == 25_400)
        #expect(LedgerRules.impliedExchangeRate(sent: vnd(1), received: vnd(1)) == nil)
    }

    @Test func amountsMustBeInTheWalletsCurrencies() {
        #expect(throws: LedgerValidationError.currencyMismatch(walletCurrency: "USD", amountCurrency: "VND")) {
            try LedgerRules.validateTransfer(TransferCandidate(
                sent: vnd(1_000), received: vnd(1_000), sourceCurrency: .usd, destinationCurrency: .vnd
            ))
        }
        #expect(throws: LedgerValidationError.currencyMismatch(walletCurrency: "VND", amountCurrency: "USD")) {
            try LedgerRules.validateTransfer(TransferCandidate(
                sent: usd(100), received: usd(100), sourceCurrency: .usd, destinationCurrency: .vnd
            ))
        }
    }

    @Test func rejectsSameWalletZeroAndArchived() {
        #expect(throws: LedgerValidationError.sameWalletTransfer) {
            try LedgerRules.validateTransfer(TransferCandidate(
                sent: vnd(1), received: vnd(1), sourceCurrency: .vnd, destinationCurrency: .vnd, isSameWallet: true
            ))
        }
        #expect(throws: LedgerValidationError.nonPositiveAmount) {
            try LedgerRules.validateTransfer(TransferCandidate(
                sent: vnd(0), received: vnd(0), sourceCurrency: .vnd, destinationCurrency: .vnd
            ))
        }
        #expect(throws: LedgerValidationError.archivedWallet) {
            try LedgerRules.validateTransfer(TransferCandidate(
                sent: vnd(1), received: vnd(1), sourceCurrency: .vnd, destinationCurrency: .vnd,
                destinationIsArchived: true
            ))
        }
    }
}

@Suite("Budget rules")
struct BudgetRulesTests {
    private let policy = CalendarPolicy(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

    private func monthly(from start: String, planned: Int64 = 4_000_000, rollover: Bool = false,
                         expenses: [BudgetExpense], at reference: String) throws -> BudgetProgress {
        try BudgetRules.progress(
            planned: vnd(planned),
            schedule: BudgetSchedule(period: .monthly, startDate: date(start)),
            rolloverEnabled: rollover,
            expenses: expenses,
            reference: date(reference),
            policy: policy
        )
    }

    // MARK: Spec example

    @Test func specExampleFoodBudget() throws {
        let progress = try monthly(
            from: "2026-10-01T00:00:00+07:00",
            expenses: [BudgetExpense(amount: vnd(2_500_000), day: day(2026, 10, 5))],
            at: "2026-10-12T09:00:00+07:00"
        )

        #expect(progress.spent == vnd(2_500_000))
        #expect(progress.remaining == vnd(1_500_000))
        #expect(progress.utilization == Decimal(string: "0.625"))
        #expect(progress.status == .onTrack)
        #expect(progress.daysLeft == 20)                 // 12–31 October
        #expect(progress.dailyAllowance == vnd(75_000))
        #expect(progress.window.firstDay == day(2026, 10, 1))
        #expect(progress.window.endDay == day(2026, 11, 1))
    }

    // MARK: Boundaries and status

    @Test func monthBoundariesUseDayKeys() throws {
        let progress = try monthly(
            from: "2026-09-01T00:00:00+07:00",
            expenses: [
                BudgetExpense(amount: vnd(100), day: day(2026, 9, 30)),
                BudgetExpense(amount: vnd(10), day: day(2026, 10, 1)),
                BudgetExpense(amount: vnd(20), day: day(2026, 10, 31)),
                BudgetExpense(amount: vnd(1_000), day: day(2026, 11, 1)),
            ],
            at: "2026-10-20T12:00:00+07:00"
        )
        #expect(progress.spent == vnd(30))
    }

    @Test func nearLimitAndOverBudget() throws {
        let reference = "2026-10-12T09:00:00+07:00"
        let near = try monthly(from: "2026-10-01T00:00:00+07:00",
                               expenses: [BudgetExpense(amount: vnd(3_200_000), day: day(2026, 10, 2))], at: reference)
        #expect(near.status == .nearLimit)

        let over = try monthly(from: "2026-10-01T00:00:00+07:00",
                               expenses: [BudgetExpense(amount: vnd(4_100_000), day: day(2026, 10, 2))], at: reference)
        #expect(over.status == .overBudget)
        #expect(over.remaining == vnd(-100_000))
        #expect(over.dailyAllowance == vnd(0))
    }

    @Test func otherCurrencyExpensesAreReportedNotCounted() throws {
        let progress = try monthly(
            from: "2026-10-01T00:00:00+07:00",
            expenses: [
                BudgetExpense(amount: usd(1_000), day: day(2026, 10, 3)),
                BudgetExpense(amount: vnd(50_000), day: day(2026, 10, 3)),
            ],
            at: "2026-10-12T09:00:00+07:00"
        )
        #expect(progress.spent == vnd(50_000))
        #expect(progress.excludedOtherCurrencyCount == 1)
    }

    // MARK: Rollover

    @Test func rolloverCarriesUnusedAmount() throws {
        let expenses = [BudgetExpense(amount: vnd(700_000), day: day(2026, 9, 10))]
        let withRollover = try monthly(from: "2026-09-01T00:00:00+07:00", planned: 1_000_000, rollover: true,
                                       expenses: expenses, at: "2026-10-05T09:00:00+07:00")
        #expect(withRollover.carriedOver == vnd(300_000))
        #expect(withRollover.available == vnd(1_300_000))

        let without = try monthly(from: "2026-09-01T00:00:00+07:00", planned: 1_000_000, rollover: false,
                                  expenses: expenses, at: "2026-10-05T09:00:00+07:00")
        #expect(without.carriedOver == vnd(0))
        #expect(without.available == vnd(1_000_000))
    }

    @Test func rolloverCarriesOverspendingAcrossSeveralPeriods() throws {
        let progress = try monthly(
            from: "2026-08-01T00:00:00+07:00", planned: 1_000_000, rollover: true,
            expenses: [
                BudgetExpense(amount: vnd(1_200_000), day: day(2026, 8, 20)),   // −200,000
                BudgetExpense(amount: vnd(900_000), day: day(2026, 9, 20)),     // +100,000
            ],
            at: "2026-10-05T09:00:00+07:00"
        )
        #expect(progress.carriedOver == vnd(-100_000))
        #expect(progress.available == vnd(900_000))
    }

    // MARK: Periods

    @Test func weeklyWindowsStartOnStartDayThenFollowMondayWeeks() throws {
        let windows = try BudgetRules.windows(
            for: BudgetSchedule(period: .weekly, startDate: date("2026-10-07T15:00:00+07:00")),
            through: date("2026-10-12T09:00:00+07:00"),
            policy: policy
        )
        #expect(windows.count == 2)
        #expect(windows[0].firstDay == day(2026, 10, 7))
        #expect(windows[0].endDay == day(2026, 10, 12))
        #expect(windows[1].firstDay == day(2026, 10, 12))
        #expect(windows[1].endDay == day(2026, 10, 19))
    }

    @Test func yearlyWindow() throws {
        let windows = try BudgetRules.windows(
            for: BudgetSchedule(period: .yearly, startDate: date("2026-01-01T00:00:00+07:00")),
            through: date("2026-10-12T09:00:00+07:00"),
            policy: policy
        )
        #expect(windows.count == 1)
        #expect(windows[0].endDay == day(2027, 1, 1))
    }

    @Test func customBudgetLifecycle() throws {
        let schedule = BudgetSchedule(
            period: .custom,
            startDate: try date("2026-10-01T00:00:00+07:00"),
            endDate: try date("2026-10-15T00:00:00+07:00")
        )
        func progress(at iso: String) throws -> BudgetProgress {
            try BudgetRules.progress(planned: vnd(1_500_000), schedule: schedule, rolloverEnabled: false,
                                     expenses: [], reference: date(iso), policy: policy)
        }

        let before = try progress(at: "2026-09-20T09:00:00+07:00")
        #expect(before.status == .notStarted)
        #expect(before.daysLeft == 15)
        #expect(before.dailyAllowance == nil)

        let during = try progress(at: "2026-10-15T20:00:00+07:00")    // last day is included
        #expect(during.status == .onTrack)
        #expect(during.daysLeft == 1)

        let after = try progress(at: "2026-10-16T00:00:00+07:00")
        #expect(after.status == .ended)
        #expect(after.daysLeft == 0)
        #expect(after.window.endDay == day(2026, 10, 16))
    }

    @Test func recurringBudgetWithEndDateStops() throws {
        let progress = try BudgetRules.progress(
            planned: vnd(1_000),
            schedule: BudgetSchedule(period: .monthly,
                                     startDate: date("2026-08-01T00:00:00+07:00"),
                                     endDate: date("2026-09-15T00:00:00+07:00")),
            rolloverEnabled: false, expenses: [],
            reference: date("2026-10-12T09:00:00+07:00"), policy: policy
        )
        #expect(progress.status == .ended)
        #expect(progress.window.firstDay == day(2026, 9, 1))
        #expect(progress.window.endDay == day(2026, 9, 16))
    }

    @Test func scheduleValidation() throws {
        #expect(throws: LedgerValidationError.budgetNeedsEndDate) {
            try BudgetRules.validateSchedule(
                BudgetSchedule(period: .custom, startDate: date("2026-10-01T00:00:00+07:00")), policy: policy)
        }
        #expect(throws: FinancialError.invalidDateRange) {
            try BudgetRules.validateSchedule(
                BudgetSchedule(period: .monthly,
                               startDate: date("2026-10-10T00:00:00+07:00"),
                               endDate: date("2026-10-01T00:00:00+07:00")), policy: policy)
        }
    }

    // MARK: Eligibility

    @Test func eligibilityFiltersKindCategoryWalletAndDuplicates() {
        let food = UUID(), coffee = UUID(), rent = UUID()
        let cash = UUID(), bank = UUID()
        let shared = UUID()
        func snapshot(id: UUID = UUID(), _ kind: TransactionKind, category: UUID?, parent: UUID? = nil,
                      wallet: UUID, _ minor: Int64) -> ExpenseSnapshot {
            ExpenseSnapshot(transactionID: id, kind: kind, categoryID: category, parentCategoryID: parent,
                            walletID: wallet, amount: vnd(minor), day: DayKey(year: 2026, month: 10, day: 1))
        }
        let snapshots = [
            snapshot(.expense, category: food, wallet: cash, 100),               // counts
            snapshot(.expense, category: coffee, parent: food, wallet: cash, 20), // child of food: counts
            snapshot(.expense, category: rent, wallet: cash, 5_000),             // other category
            snapshot(.income, category: food, wallet: cash, 999),                 // income never counts
            snapshot(.transfer, category: nil, wallet: cash, 999),                // transfer never counts
            snapshot(id: shared, .expense, category: food, wallet: bank, 7),          // counts once…
            snapshot(id: shared, .expense, category: food, wallet: bank, 7),          // …not twice
        ]

        let all = BudgetRules.eligibleExpenses(snapshots, categoryIDs: [food], walletIDs: [])
        #expect(all.map(\.amount.minorUnits) == [100, 20, 7])

        let cashOnly = BudgetRules.eligibleExpenses(snapshots, categoryIDs: [food], walletIDs: [cash])
        #expect(cashOnly.map(\.amount.minorUnits) == [100, 20])
    }
}
