import Foundation
import SwiftData

/// Version 1 of the on-device schema.
///
/// Every model lives inside a `VersionedSchema` from day one so that later
/// versions can migrate from it. Once a version ships, its models are frozen:
/// changes go into `SchemaV2` plus a stage in `FinanceMigrationPlan`.
///
/// Ledger design: a `LedgerTransaction` is the header (kind, date, category,
/// note). Its `LedgerEntry` rows move money in or out of exactly one wallet.
/// Income and expense have one entry; a transfer has two (one negative, one
/// positive) under the same header. Wallet balance = opening balance + sum of
/// that wallet's entries.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Wallet.self, LedgerCategory.self, LedgerTransaction.self, LedgerEntry.self]
    }
}

// The app always works with the current schema version through these aliases.
// V2 reuses these four models unchanged; `Budget` is declared in SchemaV2.swift.
public typealias Wallet = SchemaV1.Wallet
public typealias LedgerCategory = SchemaV1.LedgerCategory
public typealias LedgerTransaction = SchemaV1.LedgerTransaction
public typealias LedgerEntry = SchemaV1.LedgerEntry
