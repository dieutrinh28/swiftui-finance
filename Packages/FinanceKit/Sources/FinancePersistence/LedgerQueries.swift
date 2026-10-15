import Foundation
import SwiftData
import FinanceDomain

// Read-side helpers that follow relationships. They never write.
//
// Balances are derived from the ledger every time (single source of truth).
// This loads a wallet's entries into memory, which is fine for personal-scale
// data. If profiling ever shows otherwise, add a rebuildable cached projection
// rather than changing this rule.

extension Wallet {
    /// Entries not deleted in the current context.
    var liveEntries: [LedgerEntry] {
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
    public var transactionsNewestFirst: [LedgerTransaction] {
        liveEntries
            .compactMap(\.transaction)
            .filter { !$0.isDeleted }
            .sorted { $0.date > $1.date }
    }
}

extension LedgerCategory {
    var liveTransactions: [LedgerTransaction] {
        transactions.filter { !$0.isDeleted }
    }

    public var hasHistory: Bool { !liveTransactions.isEmpty }

    public var transactionsNewestFirst: [LedgerTransaction] {
        liveTransactions.sorted { $0.date > $1.date }
    }

    /// This category's transactions and its sub-categories', newest first,
    /// matching what budgets and reports count for a parent category.
    public var transactionsIncludingSubcategoriesNewestFirst: [LedgerTransaction] {
        (liveTransactions + children.filter { !$0.isDeleted }.flatMap(\.liveTransactions))
            .sorted { $0.date > $1.date }
    }
}

extension LedgerTransaction {
    var liveEntries: [LedgerEntry] {
        entries.filter { !$0.isDeleted }
    }

    /// The wallet of an income or expense, or the source wallet of a transfer.
    public var primaryWallet: Wallet? {
        kind == .transfer ? transferSource?.wallet : liveEntries.first?.wallet
    }

    /// Transfers only: the entry leaving the source wallet (negative amount).
    public var transferSource: LedgerEntry? {
        guard kind == .transfer else { return nil }
        return liveEntries.first { $0.amountMinorUnits < 0 }
    }

    /// Transfers only: the entry arriving in the destination wallet (positive amount).
    public var transferDestination: LedgerEntry? {
        guard kind == .transfer else { return nil }
        return liveEntries.first { $0.amountMinorUnits > 0 }
    }

    /// This transaction's entry in the given wallet, if any.
    public func entry(in wallet: Wallet) -> LedgerEntry? {
        liveEntries.first { $0.wallet?.id == wallet.id }
    }

    /// Read-only when any wallet involved is archived or the record is malformed.
    public var isEditable: Bool {
        kind != nil
            && !liveEntries.isEmpty
            && !liveEntries.contains { $0.wallet?.isArchived ?? true }
    }
}

extension LedgerEntry {
    /// The entry amount without sign.
    public var magnitude: Money? {
        guard let amount, let value = Int64(exactly: amount.minorUnits.magnitude) else { return nil }
        return Money(minorUnits: value, currency: amount.currency)
    }
}
