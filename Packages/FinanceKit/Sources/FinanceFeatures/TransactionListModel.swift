import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// Search, filter, sort and grouping state for the transaction list.
@MainActor
@Observable
public final class TransactionListModel {
    public enum Grouping: String, CaseIterable, Sendable {
        case day
        case month
    }

    public struct Section: Identifiable {
        /// yyyymmdd for days, yyyymm for months, 0 for an ungrouped result list.
        public let id: Int
        /// First day of the group; nil for an ungrouped list.
        public let start: Date?
        public let grouping: Grouping?
        public let transactions: [LedgerTransaction]
    }

    public var query = TransactionQuery()
    public var grouping: Grouping = .day
    /// The date filter as the user chose it, so the picker can show it again.
    public private(set) var period: ReportingPeriod?

    @ObservationIgnored private let policy: CalendarPolicy
    @ObservationIgnored private let now: () -> Date

    public init(policy: CalendarPolicy, now: @escaping () -> Date = { .now }) {
        self.policy = policy
        self.now = now
    }

    public var isGroupedByDate: Bool {
        query.sort == .newestFirst || query.sort == .oldestFirst
    }

    /// Sets (or clears) the date filter from a reporting period.
    public func setPeriod(_ period: ReportingPeriod?) throws {
        guard let period else {
            self.period = nil
            query.dayRange = nil
            return
        }
        let range = try policy.range(for: period, relativeTo: now())
        query.dayRange = policy.dayRange(for: range)
        self.period = period
    }

    public func clearFilters() {
        let sort = query.sort
        query = TransactionQuery()
        query.sort = sort
        period = nil
    }

    /// Applies the query and groups the result. Amount sorts are shown as one
    /// list, because grouping by date would hide the order.
    public func sections(from transactions: [LedgerTransaction]) -> [Section] {
        let byID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = query.apply(to: transactions.compactMap(\.summary)).compactMap { byID[$0.id] }

        guard isGroupedByDate else {
            return ordered.isEmpty ? [] : [Section(id: 0, start: nil, grouping: nil, transactions: ordered)]
        }

        // Group in order of first appearance. A dictionary (not "consecutive
        // runs") keeps ids unique even if day keys and timestamps disagree.
        var keys: [Int] = []
        var buckets: [Int: [LedgerTransaction]] = [:]
        for transaction in ordered {
            let key = groupKey(for: transaction.day)
            if buckets[key] == nil { keys.append(key) }
            buckets[key, default: []].append(transaction)
        }
        return keys.map { key in
            Section(id: key, start: start(of: key), grouping: grouping, transactions: buckets[key] ?? [])
        }
    }

    private func groupKey(for day: DayKey) -> Int {
        switch grouping {
        case .day: day.rawValue
        case .month: day.year * 100 + day.month
        }
    }

    private func start(of key: Int) -> Date? {
        switch grouping {
        case .day: policy.startOfDay(DayKey(rawValue: key))
        case .month: policy.startOfDay(DayKey(year: key / 100, month: key % 100, day: 1))
        }
    }
}
