import Foundation

// MARK: - Document

/// A complete, self-contained copy of the user's data as plain values.
///
/// The format is versioned separately from the database schema: a backup
/// written by this app version can be read by later versions, and a backup
/// from a newer app is refused instead of being half-imported.
///
/// Versions: 1 (Milestone 6); 2 (Milestone 8) adds irregular flags on
/// categories and transactions and recurring transfers. Every field added in
/// 2 is optional, so version 1 files still decode (missing = not irregular,
/// not a transfer).
public struct BackupDocument: Codable, Equatable, Sendable {
    public static let formatIdentifier = "com.ddtrinh.personalfinance.backup"
    public static let currentFormatVersion = 2

    public var format: String
    public var formatVersion: Int
    /// Database schema the data came from (informational).
    public var schemaVersion: String
    public var exportedAt: Date

    public var wallets: [WalletRecord]
    public var categories: [CategoryRecord]
    public var transactions: [TransactionRecord]
    public var budgets: [BudgetRecord]
    public var savingsGoals: [SavingsGoalRecord]
    public var recurring: [RecurringRecord]

    public init(
        schemaVersion: String,
        exportedAt: Date,
        wallets: [WalletRecord] = [],
        categories: [CategoryRecord] = [],
        transactions: [TransactionRecord] = [],
        budgets: [BudgetRecord] = [],
        savingsGoals: [SavingsGoalRecord] = [],
        recurring: [RecurringRecord] = []
    ) {
        self.format = Self.formatIdentifier
        self.formatVersion = Self.currentFormatVersion
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.wallets = wallets
        self.categories = categories
        self.transactions = transactions
        self.budgets = budgets
        self.savingsGoals = savingsGoals
        self.recurring = recurring
    }

    public struct WalletRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var type: String
        public var currencyCode: String
        public var openingBalanceMinorUnits: Int64
        public var iconName: String
        public var colorIdentifier: String
        public var note: String?
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var archivedAt: Date?

        public init(id: UUID, name: String, type: String, currencyCode: String, openingBalanceMinorUnits: Int64,
                    iconName: String, colorIdentifier: String, note: String?, sortOrder: Int,
                    createdAt: Date, updatedAt: Date, archivedAt: Date?) {
            self.id = id; self.name = name; self.type = type; self.currencyCode = currencyCode
            self.openingBalanceMinorUnits = openingBalanceMinorUnits; self.iconName = iconName
            self.colorIdentifier = colorIdentifier; self.note = note; self.sortOrder = sortOrder
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.archivedAt = archivedAt
        }
    }

    public struct CategoryRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var type: String
        public var iconName: String
        public var colorIdentifier: String
        public var seedKey: String?
        public var parentID: UUID?
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var archivedAt: Date?
        /// Format 2. nil (format 1) means false.
        public var isIrregular: Bool?

        public init(id: UUID, name: String, type: String, iconName: String, colorIdentifier: String,
                    seedKey: String?, parentID: UUID?, sortOrder: Int,
                    createdAt: Date, updatedAt: Date, archivedAt: Date?, isIrregular: Bool? = nil) {
            self.id = id; self.name = name; self.type = type; self.iconName = iconName
            self.colorIdentifier = colorIdentifier; self.seedKey = seedKey; self.parentID = parentID
            self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt
            self.archivedAt = archivedAt; self.isIrregular = isIrregular
        }
    }

    public struct EntryRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var walletID: UUID
        /// Signed: positive increases the wallet balance.
        public var amountMinorUnits: Int64
        public var currencyCode: String

        public init(id: UUID, walletID: UUID, amountMinorUnits: Int64, currencyCode: String) {
            self.id = id; self.walletID = walletID
            self.amountMinorUnits = amountMinorUnits; self.currencyCode = currencyCode
        }
    }

    public struct TransactionRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var kind: String
        public var date: Date
        public var dayKey: Int
        public var categoryID: UUID?
        public var note: String?
        public var merchant: String?
        public var exchangeRateText: String?
        public var recurringOccurrenceKey: String?
        public var createdAt: Date
        public var updatedAt: Date
        public var entries: [EntryRecord]
        /// Format 2. nil (format 1) means false.
        public var isIrregular: Bool?

        public init(id: UUID, kind: String, date: Date, dayKey: Int, categoryID: UUID?, note: String?,
                    merchant: String?, exchangeRateText: String?, recurringOccurrenceKey: String?,
                    createdAt: Date, updatedAt: Date, entries: [EntryRecord], isIrregular: Bool? = nil) {
            self.id = id; self.kind = kind; self.date = date; self.dayKey = dayKey
            self.categoryID = categoryID; self.note = note; self.merchant = merchant
            self.exchangeRateText = exchangeRateText; self.recurringOccurrenceKey = recurringOccurrenceKey
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.entries = entries
            self.isIrregular = isIrregular
        }
    }

    public struct BudgetRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var plannedAmountMinorUnits: Int64
        public var currencyCode: String
        public var period: String
        public var startDate: Date
        public var endDate: Date?
        public var categoryIDs: [UUID]
        public var walletIDs: [UUID]
        public var rolloverEnabled: Bool
        public var alertThresholdPercents: [Int]
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var archivedAt: Date?

        public init(id: UUID, name: String, plannedAmountMinorUnits: Int64, currencyCode: String, period: String,
                    startDate: Date, endDate: Date?, categoryIDs: [UUID], walletIDs: [UUID], rolloverEnabled: Bool,
                    alertThresholdPercents: [Int], sortOrder: Int, createdAt: Date, updatedAt: Date, archivedAt: Date?) {
            self.id = id; self.name = name; self.plannedAmountMinorUnits = plannedAmountMinorUnits
            self.currencyCode = currencyCode; self.period = period; self.startDate = startDate
            self.endDate = endDate; self.categoryIDs = categoryIDs; self.walletIDs = walletIDs
            self.rolloverEnabled = rolloverEnabled; self.alertThresholdPercents = alertThresholdPercents
            self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt
            self.archivedAt = archivedAt
        }
    }

    public struct ContributionRecord: Codable, Equatable, Sendable {
        public var id: UUID
        /// Signed: negative is a withdrawal.
        public var amountMinorUnits: Int64
        public var date: Date
        public var dayKey: Int
        public var note: String?
        public var createdAt: Date

        public init(id: UUID, amountMinorUnits: Int64, date: Date, dayKey: Int, note: String?, createdAt: Date) {
            self.id = id; self.amountMinorUnits = amountMinorUnits; self.date = date
            self.dayKey = dayKey; self.note = note; self.createdAt = createdAt
        }
    }

    public struct SavingsGoalRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var targetAmountMinorUnits: Int64
        public var currencyCode: String
        public var targetDate: Date?
        public var linkedWalletID: UUID?
        public var note: String?
        public var iconName: String
        public var colorIdentifier: String
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var completedAt: Date?
        public var archivedAt: Date?
        public var contributions: [ContributionRecord]

        public init(id: UUID, name: String, targetAmountMinorUnits: Int64, currencyCode: String, targetDate: Date?,
                    linkedWalletID: UUID?, note: String?, iconName: String, colorIdentifier: String, sortOrder: Int,
                    createdAt: Date, updatedAt: Date, completedAt: Date?, archivedAt: Date?,
                    contributions: [ContributionRecord]) {
            self.id = id; self.name = name; self.targetAmountMinorUnits = targetAmountMinorUnits
            self.currencyCode = currencyCode; self.targetDate = targetDate; self.linkedWalletID = linkedWalletID
            self.note = note; self.iconName = iconName; self.colorIdentifier = colorIdentifier
            self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt
            self.completedAt = completedAt; self.archivedAt = archivedAt; self.contributions = contributions
        }
    }

    public struct RecurringRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var kind: String
        public var amountMinorUnits: Int64
        public var currencyCode: String
        public var walletID: UUID
        /// Income and expenses; nil for transfers (format 2).
        public var categoryID: UUID?
        /// Transfers only (format 2).
        public var destinationWalletID: UUID?
        /// Cross-currency transfers only (format 2).
        public var receivedAmountMinorUnits: Int64?
        public var frequency: String
        public var interval: Int
        public var startDate: Date
        public var endDate: Date?
        public var note: String?
        public var reminderEnabled: Bool
        public var reminderMinutes: Int
        public var pausedAt: Date?
        public var handledOccurrenceKeys: [String]
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID, name: String, kind: String, amountMinorUnits: Int64, currencyCode: String,
                    walletID: UUID, categoryID: UUID?, frequency: String, interval: Int, startDate: Date,
                    endDate: Date?, note: String?, reminderEnabled: Bool, reminderMinutes: Int, pausedAt: Date?,
                    handledOccurrenceKeys: [String], sortOrder: Int, createdAt: Date, updatedAt: Date,
                    destinationWalletID: UUID? = nil, receivedAmountMinorUnits: Int64? = nil) {
            self.id = id; self.name = name; self.kind = kind; self.amountMinorUnits = amountMinorUnits
            self.currencyCode = currencyCode; self.walletID = walletID; self.categoryID = categoryID
            self.destinationWalletID = destinationWalletID; self.receivedAmountMinorUnits = receivedAmountMinorUnits
            self.frequency = frequency; self.interval = interval; self.startDate = startDate
            self.endDate = endDate; self.note = note; self.reminderEnabled = reminderEnabled
            self.reminderMinutes = reminderMinutes; self.pausedAt = pausedAt
            self.handledOccurrenceKeys = handledOccurrenceKeys; self.sortOrder = sortOrder
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }
}

// MARK: - Summary and errors

/// What a backup contains, shown before the user confirms a restore.
public struct BackupSummary: Equatable, Sendable {
    public let exportedAt: Date
    public let wallets: Int
    public let categories: Int
    public let transactions: Int
    public let budgets: Int
    public let savingsGoals: Int
    public let recurring: Int
}

public enum BackupError: Error, Equatable, Sendable {
    /// Not JSON, or JSON that doesn't match the format.
    case unreadable(details: String)
    /// Some other JSON file.
    case notABackup
    /// Written by a newer version of the app.
    case newerFormat(version: Int)
    case duplicateID(entity: String)
    case invalidValue(field: String, value: String)
    case missingReference(entity: String, id: UUID)
    case invalidTransaction(id: UUID)
    case categoryCycle
}

extension BackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "This file can't be read as a backup. It may be damaged.", bundle: .l10n)
        case .notABackup:
            String(localized: "This file is not a Personal Finance backup.", bundle: .l10n)
        case .newerFormat:
            String(localized: "This backup was made by a newer version of the app. Update the app, then try again.", bundle: .l10n)
        case .duplicateID(let entity):
            String(localized: "The backup is inconsistent: two \(entity) records share an identifier.", bundle: .l10n)
        case .invalidValue(let field, let value):
            String(localized: "The backup contains an invalid value for \(field): \(value).", bundle: .l10n)
        case .missingReference(let entity, _):
            String(localized: "The backup is incomplete: a \(entity) it refers to is missing.", bundle: .l10n)
        case .invalidTransaction:
            String(localized: "The backup contains a transaction whose amounts don't add up.", bundle: .l10n)
        case .categoryCycle:
            String(localized: "The backup contains categories that are their own parent.", bundle: .l10n)
        }
    }
}

// MARK: - Codec

/// JSON encoding of `BackupDocument`: sorted keys and ISO 8601 dates with
/// milliseconds, so files are stable, diffable and readable.
public enum BackupCodec {
    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: dateStyle) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(text)")
        }

        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw BackupError.unreadable(details: String(describing: error))
        }
        guard header.format == BackupDocument.formatIdentifier, let version = header.formatVersion else {
            throw BackupError.notABackup
        }
        guard version <= BackupDocument.currentFormatVersion else {
            throw BackupError.newerFormat(version: version)
        }
        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.unreadable(details: String(describing: error))
        }
    }

    /// Read first, so any other JSON file is reported as "not a backup".
    private struct Header: Decodable {
        let format: String?
        let formatVersion: Int?
    }

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
