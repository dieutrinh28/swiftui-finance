import Foundation
import SwiftData
import FinanceDomain

/// Reads the ledger into plain values for reports, search and filtering.
/// Never writes.
public struct ReportService {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// One consistent copy of wallets, entries and categories.
    /// Throws instead of skipping a record it can't read, so totals are never silently wrong.
    public func snapshot() throws -> LedgerSnapshot {
        let wallets = try context.fetch(FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\.sortOrder)]))
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        var entryDescriptor = FetchDescriptor<LedgerEntry>()
        entryDescriptor.relationshipKeyPathsForPrefetching = [\.transaction, \.wallet]
        let entries = try context.fetch(entryDescriptor)

        return LedgerSnapshot(
            wallets: try wallets.map { wallet in
                guard let opening = wallet.openingBalance else { throw LedgerValidationError.corruptRecord }
                return WalletSnapshot(
                    id: wallet.id,
                    name: wallet.name,
                    accountClass: wallet.type.accountClass,
                    openingBalance: opening,
                    isArchived: wallet.isArchived
                )
            },
            entries: try entries.filter { !$0.isDeleted }.map { entry in
                guard let transaction = entry.transaction,
                      let kind = transaction.kind,
                      let wallet = entry.wallet,
                      let amount = entry.amount
                else { throw LedgerValidationError.corruptRecord }
                return EntrySnapshot(
                    transactionID: transaction.id,
                    kind: kind,
                    day: transaction.day,
                    walletID: wallet.id,
                    amount: amount,
                    categoryID: transaction.category?.id,
                    isIrregular: transaction.isIrregular
                )
            },
            categories: categories.map {
                CategorySnapshot(id: $0.id, name: $0.name, iconName: $0.iconName, colorIdentifier: $0.colorIdentifier,
                                 parentID: $0.parent?.id)
            }
        )
    }
}

extension LedgerTransaction {
    /// Search/filter view of this transaction; nil when the record is malformed.
    public var summary: TransactionSummary? {
        guard let kind, let amount = displayAmount else { return nil }
        let wallets = liveEntries.compactMap(\.wallet)
        let text = [note, merchant, category?.name, category?.parent?.name]
            .compactMap { $0 }
            + wallets.map(\.name)
        return TransactionSummary(
            id: id,
            kind: kind,
            date: date,
            day: day,
            amount: amount,
            walletIDs: Set(wallets.map(\.id)),
            categoryID: category?.id,
            parentCategoryID: category?.parent?.id,
            searchableText: text.joined(separator: " · ")
        )
    }
}
