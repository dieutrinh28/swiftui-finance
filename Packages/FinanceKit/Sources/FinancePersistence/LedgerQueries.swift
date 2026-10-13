import Foundation
import SwiftData
import FinanceDomain

// Read-side helpers that follow relationships. They never write.
//
// Balances are derived from the ledger every time (single source of truth).
// This loads a wallet's entries into memory, which is fine for personal-scale
// data. If profiling ever shows otherwise, add a rebuildable cached projection
// rather than changing this rule.

extension SchemaV1.Wallet {
    /// Entries not deleted in the current context.
    var liveEntries: [SchemaV1.LedgerEntry] {
        entries.filter { !$0.isDeleted }
    }

    /// True once any transaction references this wallet.
    public var hasHistory: Bool { !liveEntries.isEmpty }

    /// Opening balance plus every ledger entry. Throws instead of guessing
    /// when stored data is unreadable or mixes currencies.
    public func currentBalance() throws -> Money {
        guard let opening = openingBalance else { throw LedgerValidationError.corruptRecord }
        let amounts = try liveEntries.map { entry -> Money in
            guard let amount = entry.amount else { throw LedgerValidationError.corruptRecord }
            return amount
        }
        return try LedgerRules.balance(opening: opening, entries: amounts)
    }

    /// Transactions touching this wallet, newest first.
    public var transactionsNewestFirst: [SchemaV1.LedgerTransaction] {
        liveEntries
            .compactMap(\.transaction)
            .filter { !$0.isDeleted }
            .sorted { $0.date > $1.date }
    }
}

extension SchemaV1.LedgerCategory {
    var liveTransactions: [SchemaV1.LedgerTransaction] {
        transactions.filter { !$0.isDeleted }
    }

    public var hasHistory: Bool { !liveTransactions.isEmpty }

    public var transactionsNewestFirst: [SchemaV1.LedgerTransaction] {
        liveTransactions.sorted { $0.date > $1.date }
    }
}

extension SchemaV1.LedgerTransaction {
    var liveEntries: [SchemaV1.LedgerEntry] {
        entries.filter { !$0.isDeleted }
    }

    /// The wallet of an income or expense, or the source wallet of a transfer.
    public var primaryWallet: SchemaV1.Wallet? {
        kind == .transfer ? transferSource?.wallet : liveEntries.first?.wallet
    }

    /// Transfers only: the entry leaving the source wallet (negative amount).
    public var transferSource: SchemaV1.LedgerEntry? {
        guard kind == .transfer else { return nil }
        return liveEntries.first { $0.amountMinorUnits < 0 }
    }

    /// Transfers only: the entry arriving in the destination wallet (positive amount).
    public var transferDestination: SchemaV1.LedgerEntry? {
        guard kind == .transfer else { return nil }
        return liveEntries.first { $0.amountMinorUnits > 0 }
    }

    /// This transaction's entry in the given wallet, if any.
    public func entry(in wallet: SchemaV1.Wallet) -> SchemaV1.LedgerEntry? {
        liveEntries.first { $0.wallet?.id == wallet.id }
    }

    /// Read-only when any wallet involved is archived or the record is malformed.
    public var isEditable: Bool {
        kind != nil
            && !liveEntries.isEmpty
            && !liveEntries.contains { $0.wallet?.isArchived ?? true }
    }
}

extension SchemaV1.LedgerEntry {
    /// The entry amount without sign.
    public var magnitude: Money? {
        guard let amount, let value = Int64(exactly: amount.minorUnits.magnitude) else { return nil }
        return Money(minorUnits: value, currency: amount.currency)
    }
}
