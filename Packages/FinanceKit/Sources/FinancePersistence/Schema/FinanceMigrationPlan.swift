import SwiftData

/// Ordered list of every schema version that has shipped, oldest first.
///
/// To change the schema: add `SchemaV(n+1)` with the changed or new models
/// (unchanged models may be reused from the previous version), point the
/// typealiases at the new types, then append a stage here. Add a test that
/// opens a store written with the previous version.
public enum FinanceMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }

    /// Adds the Budget entity. No existing data changes.
    static var migrateV1toV2: MigrationStage {
        .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
    }

    /// Adds SavingsGoal, SavingsContribution and RecurringTransaction.
    static var migrateV2toV3: MigrationStage {
        .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
    }

    /// Irregular-expense flags (default false), recurring transfers (new
    /// optional fields, `categoryID` becomes optional). No data rewrite.
    static var migrateV3toV4: MigrationStage {
        .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self)
    }
}
