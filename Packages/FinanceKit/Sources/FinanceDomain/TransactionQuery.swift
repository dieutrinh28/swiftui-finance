import Foundation

/// A plain-value view of a transaction for searching, filtering and sorting.
public struct TransactionSummary: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: TransactionKind
    public var date: Date
    public var day: DayKey
    /// Unsigned display amount (the amount sent, for a transfer).
    public var amount: Money
    /// One wallet for income/expense, two for a transfer.
    public var walletIDs: Set<UUID>
    public var categoryID: UUID?
    /// The parent of `categoryID` when it is a sub-category.
    public var parentCategoryID: UUID?
    /// Note, merchant, category (and parent) and wallet names; searched without regard to case or accents.
    public var searchableText: String

    public init(
        id: UUID,
        kind: TransactionKind,
        date: Date,
        day: DayKey,
        amount: Money,
        walletIDs: Set<UUID>,
        categoryID: UUID?,
        parentCategoryID: UUID? = nil,
        searchableText: String
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.day = day
        self.amount = amount
        self.walletIDs = walletIDs
        self.categoryID = categoryID
        self.parentCategoryID = parentCategoryID
        self.searchableText = searchableText
    }
}

public enum TransactionSort: String, CaseIterable, Sendable {
    case newestFirst
    case oldestFirst
    case largestFirst
    case smallestFirst
}

/// Search, filters and sort order for the transaction list.
///
/// Empty sets and nil bounds mean "no filter". Text search splits the query into
/// words; every word must appear (ignoring case and Vietnamese accents, so "pho"
/// finds "Phở" and "da" finds "Đá"). Amount bounds are inclusive and compare
/// major units in each transaction's own currency. Choosing a category also
/// matches its sub-categories, as budgets and reports count them.
public struct TransactionQuery: Sendable, Equatable {
    public var searchText = ""
    public var dayRange: DayRange?
    public var kinds: Set<TransactionKind> = []
    public var walletIDs: Set<UUID> = []
    public var categoryIDs: Set<UUID> = []
    public var minimumAmount: Decimal?
    public var maximumAmount: Decimal?
    public var sort: TransactionSort = .newestFirst

    public init() {}

    /// Number of active filters, excluding search text and sort order.
    public var activeFilterCount: Int {
        [
            dayRange != nil,
            !kinds.isEmpty,
            !walletIDs.isEmpty,
            !categoryIDs.isEmpty,
            minimumAmount != nil || maximumAmount != nil,
        ].filter { $0 }.count
    }

    public var isFiltering: Bool {
        activeFilterCount > 0 || !Self.normalize(searchText).trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func matches(_ summary: TransactionSummary) -> Bool {
        if let dayRange, !dayRange.contains(summary.day) { return false }
        if !kinds.isEmpty, !kinds.contains(summary.kind) { return false }
        if !walletIDs.isEmpty, walletIDs.isDisjoint(with: summary.walletIDs) { return false }
        if !categoryIDs.isEmpty {
            let parentMatches = summary.parentCategoryID.map { categoryIDs.contains($0) } ?? false
            guard let category = summary.categoryID, categoryIDs.contains(category) || parentMatches
            else { return false }
        }
        let amount = summary.amount.majorUnits
        if let minimumAmount, amount < minimumAmount { return false }
        if let maximumAmount, amount > maximumAmount { return false }

        let words = Self.normalize(searchText).split(whereSeparator: \.isWhitespace)
        if !words.isEmpty {
            let haystack = Self.normalize(summary.searchableText)
            guard words.allSatisfy({ haystack.contains($0) }) else { return false }
        }
        return true
    }

    /// Filters and sorts. Ties are broken by date (newest first), then id, so the order is stable.
    public func apply(to summaries: [TransactionSummary]) -> [TransactionSummary] {
        summaries.filter(matches).sorted { lhs, rhs in
            switch sort {
            case .newestFirst:
                if lhs.date != rhs.date { return lhs.date > rhs.date }
            case .oldestFirst:
                if lhs.date != rhs.date { return lhs.date < rhs.date }
            case .largestFirst:
                if lhs.amount.majorUnits != rhs.amount.majorUnits { return lhs.amount.majorUnits > rhs.amount.majorUnits }
            case .smallestFirst:
                if lhs.amount.majorUnits != rhs.amount.majorUnits { return lhs.amount.majorUnits < rhs.amount.majorUnits }
            }
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Lower-cased, accents removed, "đ" folded to "d".
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
    }
}
