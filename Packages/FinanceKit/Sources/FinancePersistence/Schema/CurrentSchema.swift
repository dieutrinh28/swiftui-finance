import SwiftData

// The app always works with the current schema version through these aliases.
// When a new version copies a model, point its alias at the new copy; older
// versions keep their own frozen classes for migration only.
//
// Current version: SchemaV4.

public typealias Wallet = SchemaV4.Wallet
public typealias LedgerCategory = SchemaV4.LedgerCategory
public typealias LedgerTransaction = SchemaV4.LedgerTransaction
public typealias LedgerEntry = SchemaV4.LedgerEntry
public typealias Budget = SchemaV2.Budget
public typealias SavingsGoal = SchemaV3.SavingsGoal
public typealias SavingsContribution = SchemaV3.SavingsContribution
public typealias RecurringTransaction = SchemaV4.RecurringTransaction
