import Foundation
import Observation
import FinanceDomain

/// The result of loading data for a screen.
public enum LoadState<Value> {
    case idle
    case loaded(Value)
    case failed(any Error)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var error: (any Error)? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// Everything the Home dashboard shows, computed from one ledger snapshot.
public struct DashboardOverview: Sendable {
    public let range: DateRange
    /// The currency charts and breakdowns use (the default currency when present).
    public let primaryCurrency: CurrencyDefinition
    /// Assets, liabilities and net worth now, one per currency.
    public let positions: [CurrencyPosition]
    /// Income, expenses and net in the selected period, one per currency.
    public let cashFlow: [CashFlowSummary]
    /// Top expense categories in the period (primary currency), rest folded into "other".
    public let topCategories: [AmountShare]
    /// The last six months of income and expenses (primary currency).
    public let monthlyTrend: [PeriodCashFlow]
    /// Archived wallets that still hold money; they are included in the totals.
    public let archivedWalletsWithBalance: Int
    public let categories: [UUID: CategorySnapshot]
    public let hasWallets: Bool
}

/// Home dashboard state: the selected period and the overview computed for it.
///
/// `reload()` reads one snapshot and derives every number from it, so the
/// figures on screen always agree with each other and with the ledger.
@MainActor
@Observable
public final class DashboardModel {
    public static let categoryLimit = 5
    public static let trendMonths = 6

    public var period: ReportingPeriod = .thisMonth
    public private(set) var state: LoadState<DashboardOverview> = .idle

    @ObservationIgnored private let loadSnapshot: () throws -> LedgerSnapshot
    @ObservationIgnored private let policy: CalendarPolicy
    @ObservationIgnored private let now: () -> Date

    public init(
        policy: CalendarPolicy,
        now: @escaping () -> Date = { .now },
        loadSnapshot: @escaping () throws -> LedgerSnapshot
    ) {
        self.policy = policy
        self.now = now
        self.loadSnapshot = loadSnapshot
    }

    public func reload() {
        do {
            let snapshot = try loadSnapshot()
            let reference = now()
            let range = try policy.range(for: period, relativeTo: reference)
            let dayRange = policy.dayRange(for: range)
            let primary = snapshot.currencies.first ?? CurrencyCatalog.defaultCurrency

            state = .loaded(DashboardOverview(
                range: range,
                primaryCurrency: primary,
                positions: try ReportRules.positions(snapshot),
                cashFlow: try ReportRules.cashFlow(snapshot, in: dayRange),
                topCategories: try ReportRules.top(
                    ReportRules.expensesByCategory(snapshot, in: dayRange, currency: primary),
                    limit: Self.categoryLimit
                ),
                monthlyTrend: try ReportRules.cashFlowTrend(
                    snapshot,
                    periods: policy.monthRanges(endingWith: reference, count: Self.trendMonths),
                    currency: primary,
                    policy: policy
                ),
                archivedWalletsWithBalance: try ReportRules.archivedWalletsWithBalance(snapshot),
                categories: Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) }),
                hasWallets: !snapshot.wallets.isEmpty
            ))
        } catch {
            state = .failed(error)
        }
    }
}

/// Everything the Reports screen shows for one period and currency.
public struct ReportOverview: Sendable {
    public let range: DateRange
    public let currency: CurrencyDefinition
    public let availableCurrencies: [CurrencyDefinition]
    public let cashFlow: CashFlowSummary
    public let expensesByCategory: [AmountShare]
    public let expensesByWallet: [AmountShare]
    /// Daily expenses with a running total across the period.
    public let dailyExpenses: [DailyAmount]
    /// The last twelve months of income, expenses and net.
    public let monthlyCashFlow: [PeriodCashFlow]
    /// Net worth at the end of each of the last twelve months.
    public let netWorthTrend: [NetWorthPoint]
    public let categories: [UUID: CategorySnapshot]
    public let wallets: [UUID: WalletSnapshot]
}

/// Reports screen state: period, currency and the computed report.
@MainActor
@Observable
public final class ReportsModel {
    public static let trendMonths = 12

    public var period: ReportingPeriod = .thisMonth
    /// nil means the primary currency.
    public var currency: CurrencyDefinition?
    public private(set) var state: LoadState<ReportOverview> = .idle

    @ObservationIgnored private let loadSnapshot: () throws -> LedgerSnapshot
    @ObservationIgnored private let policy: CalendarPolicy
    @ObservationIgnored private let now: () -> Date

    public init(
        policy: CalendarPolicy,
        now: @escaping () -> Date = { .now },
        loadSnapshot: @escaping () throws -> LedgerSnapshot
    ) {
        self.policy = policy
        self.now = now
        self.loadSnapshot = loadSnapshot
    }

    public func reload() {
        do {
            let snapshot = try loadSnapshot()
            let reference = now()
            let range = try policy.range(for: period, relativeTo: reference)
            let dayRange = policy.dayRange(for: range)
            let available = snapshot.currencies
            let selected = currency.flatMap { available.contains($0) ? $0 : nil }
                ?? available.first
                ?? CurrencyCatalog.defaultCurrency
            let months = try policy.monthRanges(endingWith: reference, count: Self.trendMonths)

            state = .loaded(ReportOverview(
                range: range,
                currency: selected,
                availableCurrencies: available,
                cashFlow: try ReportRules.cashFlow(snapshot, in: dayRange, currency: selected),
                expensesByCategory: try ReportRules.expensesByCategory(snapshot, in: dayRange, currency: selected),
                expensesByWallet: try ReportRules.expensesByWallet(snapshot, in: dayRange, currency: selected),
                dailyExpenses: try ReportRules.dailyExpenses(snapshot, in: range, currency: selected, policy: policy),
                monthlyCashFlow: try ReportRules.cashFlowTrend(snapshot, periods: months, currency: selected, policy: policy),
                netWorthTrend: try ReportRules.netWorthTrend(snapshot, periods: months, currency: selected, policy: policy),
                categories: Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) }),
                wallets: Dictionary(uniqueKeysWithValues: snapshot.wallets.map { ($0.id, $0) })
            ))
        } catch {
            state = .failed(error)
        }
    }
}
