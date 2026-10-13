import Foundation

// MARK: - Day ranges

/// A half-open range of calendar days `[first, end)`, compared by day key.
public struct DayRange: Hashable, Sendable {
    public let first: DayKey
    /// Exclusive.
    public let end: DayKey

    public init(first: DayKey, end: DayKey) {
        self.first = first
        self.end = end
    }

    public func contains(_ day: DayKey) -> Bool {
        day >= first && day < end
    }
}

extension CalendarPolicy {
    public func dayRange(for range: DateRange) -> DayRange {
        DayRange(first: dayKey(for: range.start), end: dayKey(for: range.end))
    }

    /// `count` calendar months ending with the month that contains `reference`, oldest first.
    public func monthRanges(endingWith reference: Date, count: Int) throws -> [DateRange] {
        guard count > 0 else { return [] }
        let current = try range(for: .thisMonth, relativeTo: reference)
        return try (0..<count).reversed().map { offset in
            guard let anchor = calendar.date(byAdding: .month, value: -offset, to: current.start),
                  let interval = calendar.dateInterval(of: .month, for: anchor)
            else { throw FinancialError.invalidDateRange }
            return try DateRange(start: interval.start, end: interval.end)
        }
    }

    /// Every calendar day in `range`, in order.
    public func days(in range: DateRange) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: range.start)
        while cursor < range.end, result.count < 3_700 {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}

// MARK: - Snapshots

/// Plain-value copies of the ledger used by reports. Built once per refresh,
/// so every number on a screen comes from the same consistent read.
public struct WalletSnapshot: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var accountClass: AccountClass
    public var openingBalance: Money
    public var isArchived: Bool

    public init(id: UUID, name: String, accountClass: AccountClass, openingBalance: Money, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.accountClass = accountClass
        self.openingBalance = openingBalance
        self.isArchived = isArchived
    }
}

/// One ledger entry: a signed amount in one wallet.
public struct EntrySnapshot: Sendable, Equatable {
    public var transactionID: UUID
    public var kind: TransactionKind
    public var day: DayKey
    public var walletID: UUID
    /// Signed, in the wallet's currency.
    public var amount: Money
    public var categoryID: UUID?

    public init(transactionID: UUID, kind: TransactionKind, day: DayKey, walletID: UUID, amount: Money, categoryID: UUID? = nil) {
        self.transactionID = transactionID
        self.kind = kind
        self.day = day
        self.walletID = walletID
        self.amount = amount
        self.categoryID = categoryID
    }
}

public struct CategorySnapshot: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var iconName: String
    public var colorIdentifier: String

    public init(id: UUID, name: String, iconName: String, colorIdentifier: String) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorIdentifier = colorIdentifier
    }
}

public struct LedgerSnapshot: Sendable, Equatable {
    public var wallets: [WalletSnapshot]
    public var entries: [EntrySnapshot]
    public var categories: [CategorySnapshot]

    public init(wallets: [WalletSnapshot] = [], entries: [EntrySnapshot] = [], categories: [CategorySnapshot] = []) {
        self.wallets = wallets
        self.entries = entries
        self.categories = categories
    }

    public static let empty = LedgerSnapshot()

    /// Currencies that appear in any wallet, default currency first.
    public var currencies: [CurrencyDefinition] {
        ReportRules.ordered(Set(wallets.map(\.openingBalance.currency)))
    }
}

// MARK: - Results

/// Where the money is, for one currency, at a point in time.
public struct CurrencyPosition: Sendable, Equatable {
    public let currency: CurrencyDefinition
    /// Sum of asset-wallet balances.
    public let assets: Money
    /// Amount owed on liability wallets, as a positive number
    /// (negative only if a card is in credit).
    public let liabilities: Money
    /// assets − liabilities = sum of every wallet balance.
    public let netWorth: Money
}

/// Where the money went, for one currency, in a period. Transfers are excluded.
public struct CashFlowSummary: Sendable, Equatable {
    public let currency: CurrencyDefinition
    public let income: Money
    public let expenses: Money
    /// income − expenses
    public let net: Money
}

/// One slice of a breakdown.
public struct AmountShare: Sendable, Equatable, Identifiable {
    public enum Key: Hashable, Sendable {
        case category(UUID)
        case wallet(UUID)
        case uncategorized
        /// Everything beyond the top slices.
        case other
    }

    public let key: Key
    public let amount: Money
    /// amount ÷ total of the breakdown (0…1).
    public let share: Decimal

    public var id: Key { key }
}

public struct PeriodCashFlow: Sendable, Equatable, Identifiable {
    public let start: Date
    public let range: DayRange
    public let income: Money
    public let expenses: Money
    public let net: Money

    public var id: Date { start }
}

public struct NetWorthPoint: Sendable, Equatable, Identifiable {
    /// First day of the period this point closes.
    public let start: Date
    public let netWorth: Money

    public var id: Date { start }
}

public struct DailyAmount: Sendable, Equatable, Identifiable {
    public let date: Date
    public let amount: Money
    /// Running total from the first day of the range.
    public let cumulative: Money

    public var id: Date { date }
}

// MARK: - Rules

/// Report calculations over a `LedgerSnapshot`. See docs/ARCHITECTURE.md, "Reports".
///
/// - Currencies are never mixed: every result is per currency.
/// - Transfers are never income or expenses.
/// - Archived wallets are included in balances and net worth (archiving hides
///   a wallet, it doesn't make its money disappear) and in historical cash flow.
/// - Opening balances count from the beginning of time; they are not income.
public enum ReportRules {
    // MARK: Balances

    /// Balance of every wallet, counting entries before `day` (all entries when nil).
    public static func balances(_ snapshot: LedgerSnapshot, before day: DayKey? = nil) throws -> [UUID: Money] {
        var result = Dictionary(uniqueKeysWithValues: snapshot.wallets.map { ($0.id, $0.openingBalance) })
        for entry in snapshot.entries {
            if let day, entry.day >= day { continue }
            guard let balance = result[entry.walletID] else { continue }
            result[entry.walletID] = try balance.adding(entry.amount)
        }
        return result
    }

    /// Assets, liabilities and net worth per currency.
    public static func positions(_ snapshot: LedgerSnapshot, before day: DayKey? = nil) throws -> [CurrencyPosition] {
        let balances = try balances(snapshot, before: day)
        var assets: [CurrencyDefinition: Money] = [:]
        var owed: [CurrencyDefinition: Money] = [:]
        for wallet in snapshot.wallets {
            guard let balance = balances[wallet.id] else { continue }
            let currency = balance.currency
            switch wallet.accountClass {
            case .asset:
                assets[currency] = try (assets[currency] ?? .zero(currency)).adding(balance)
            case .liability:
                owed[currency] = try (owed[currency] ?? .zero(currency)).subtracting(balance)
            }
        }
        return try snapshot.currencies.map { currency in
            let assetTotal = assets[currency] ?? .zero(currency)
            let owedTotal = owed[currency] ?? .zero(currency)
            return CurrencyPosition(
                currency: currency,
                assets: assetTotal,
                liabilities: owedTotal,
                netWorth: try assetTotal.subtracting(owedTotal)
            )
        }
    }

    /// Archived wallets whose balance is not zero (shown as a note next to totals).
    public static func archivedWalletsWithBalance(_ snapshot: LedgerSnapshot) throws -> Int {
        let balances = try balances(snapshot)
        return snapshot.wallets.filter { $0.isArchived && !(balances[$0.id]?.isZero ?? true) }.count
    }

    // MARK: Cash flow

    public static func cashFlow(_ snapshot: LedgerSnapshot, in range: DayRange) throws -> [CashFlowSummary] {
        var income: [CurrencyDefinition: Money] = [:]
        var expenses: [CurrencyDefinition: Money] = [:]
        for entry in snapshot.entries where range.contains(entry.day) {
            let currency = entry.amount.currency
            switch entry.kind {
            case .income:
                income[currency] = try (income[currency] ?? .zero(currency)).adding(entry.amount)
            case .expense:
                expenses[currency] = try (expenses[currency] ?? .zero(currency)).subtracting(entry.amount)
            case .transfer:
                continue
            }
        }
        let currencies = ordered(Set(snapshot.currencies).union(income.keys).union(expenses.keys))
        return try currencies.map { currency in
            let incomeTotal = income[currency] ?? .zero(currency)
            let expenseTotal = expenses[currency] ?? .zero(currency)
            return CashFlowSummary(
                currency: currency,
                income: incomeTotal,
                expenses: expenseTotal,
                net: try incomeTotal.subtracting(expenseTotal)
            )
        }
    }

    public static func cashFlow(
        _ snapshot: LedgerSnapshot,
        in range: DayRange,
        currency: CurrencyDefinition
    ) throws -> CashFlowSummary {
        try cashFlow(snapshot, in: range).first { $0.currency == currency }
            ?? CashFlowSummary(currency: currency, income: .zero(currency), expenses: .zero(currency), net: .zero(currency))
    }

    // MARK: Breakdowns

    /// Expenses per category in `range` for one currency, largest first.
    public static func expensesByCategory(
        _ snapshot: LedgerSnapshot,
        in range: DayRange,
        currency: CurrencyDefinition
    ) throws -> [AmountShare] {
        try breakdown(snapshot, in: range, currency: currency) { entry in
            entry.categoryID.map(AmountShare.Key.category) ?? .uncategorized
        }
    }

    /// Expenses per wallet in `range` for one currency, largest first.
    public static func expensesByWallet(
        _ snapshot: LedgerSnapshot,
        in range: DayRange,
        currency: CurrencyDefinition
    ) throws -> [AmountShare] {
        try breakdown(snapshot, in: range, currency: currency) { .wallet($0.walletID) }
    }

    /// Keeps the `limit` largest slices and folds the rest into one `.other` slice.
    public static func top(_ shares: [AmountShare], limit: Int) throws -> [AmountShare] {
        guard shares.count > limit, limit > 0, let currency = shares.first?.amount.currency else { return shares }
        let kept = Array(shares.prefix(limit))
        let rest = shares.dropFirst(limit)
        let amount = try Money.sum(rest.map(\.amount), currency: currency)
        let share = rest.reduce(Decimal(0)) { $0 + $1.share }
        return kept + [AmountShare(key: .other, amount: amount, share: share)]
    }

    // MARK: Trends

    /// Income, expenses and net for each period, for one currency.
    public static func cashFlowTrend(
        _ snapshot: LedgerSnapshot,
        periods: [DateRange],
        currency: CurrencyDefinition,
        policy: CalendarPolicy
    ) throws -> [PeriodCashFlow] {
        try periods.map { period in
            let range = policy.dayRange(for: period)
            let flow = try cashFlow(snapshot, in: range, currency: currency)
            return PeriodCashFlow(start: period.start, range: range, income: flow.income, expenses: flow.expenses, net: flow.net)
        }
    }

    /// Net worth at the end of each period, for one currency.
    public static func netWorthTrend(
        _ snapshot: LedgerSnapshot,
        periods: [DateRange],
        currency: CurrencyDefinition,
        policy: CalendarPolicy
    ) throws -> [NetWorthPoint] {
        try periods.map { period in
            let end = policy.dayKey(for: period.end)
            let net = try positions(snapshot, before: end).first { $0.currency == currency }?.netWorth ?? .zero(currency)
            return NetWorthPoint(start: period.start, netWorth: net)
        }
    }

    /// Expenses per day in `range` with a running total, for one currency.
    public static func dailyExpenses(
        _ snapshot: LedgerSnapshot,
        in range: DateRange,
        currency: CurrencyDefinition,
        policy: CalendarPolicy
    ) throws -> [DailyAmount] {
        var perDay: [DayKey: Money] = [:]
        let dayRange = policy.dayRange(for: range)
        for entry in snapshot.entries
        where entry.kind == .expense && entry.amount.currency == currency && dayRange.contains(entry.day) {
            perDay[entry.day] = try (perDay[entry.day] ?? .zero(currency)).subtracting(entry.amount)
        }
        var running = Money.zero(currency)
        return try policy.days(in: range).map { date in
            let amount = perDay[policy.dayKey(for: date)] ?? .zero(currency)
            running = try running.adding(amount)
            return DailyAmount(date: date, amount: amount, cumulative: running)
        }
    }

    // MARK: Helpers

    /// Default currency first, then alphabetical by code.
    public static func ordered(_ currencies: Set<CurrencyDefinition>) -> [CurrencyDefinition] {
        currencies.sorted { lhs, rhs in
            if lhs == CurrencyCatalog.defaultCurrency { return rhs != lhs }
            if rhs == CurrencyCatalog.defaultCurrency { return false }
            return lhs.code < rhs.code
        }
    }

    private static func breakdown(
        _ snapshot: LedgerSnapshot,
        in range: DayRange,
        currency: CurrencyDefinition,
        key: (EntrySnapshot) -> AmountShare.Key
    ) throws -> [AmountShare] {
        var totals: [AmountShare.Key: Money] = [:]
        var order: [AmountShare.Key] = []
        for entry in snapshot.entries
        where entry.kind == .expense && entry.amount.currency == currency && range.contains(entry.day) {
            let slice = key(entry)
            if totals[slice] == nil { order.append(slice) }
            totals[slice] = try (totals[slice] ?? .zero(currency)).subtracting(entry.amount)
        }
        let grandTotal = try Money.sum(totals.values, currency: currency)
        return try order
            .compactMap { slice -> AmountShare? in
                guard let amount = totals[slice] else { return nil }
                let share = try amount.ratio(to: grandTotal) ?? 0
                return AmountShare(key: slice, amount: amount, share: share)
            }
            .sorted { $0.amount.minorUnits > $1.amount.minorUnits }
    }
}
