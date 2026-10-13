import Foundation
import SwiftData
import FinanceDomain

/// What an import will do, shown before the user confirms.
public struct ImportPlan: Equatable, Sendable {
    public struct NewWallet: Equatable, Sendable {
        public let name: String
        public let currency: CurrencyDefinition

        public init(name: String, currency: CurrencyDefinition) {
            self.name = name
            self.currency = currency
        }
    }

    public struct NewCategory: Equatable, Sendable {
        /// "Food" or "Food / Coffee".
        public let path: String
        public let type: CategoryType

        public init(path: String, type: CategoryType) {
            self.path = path
            self.type = type
        }
    }

    /// Rows that will be imported.
    public var ready: [ImportedTransaction] = []
    /// Same day, kind, wallet and amount as a transaction already in the app.
    /// Skipped unless the user chooses to import them too.
    public var possibleDuplicates: [ImportedTransaction] = []
    /// Rows whose ID is already in the app (or repeated in the file). Always skipped.
    public var alreadyImported = 0
    /// Rows that can't be imported, with the reason.
    public var issues: [ImportIssue] = []
    /// Created during the import, because no wallet/category has that name.
    public var newWallets: [NewWallet] = []
    public var newCategories: [NewCategory] = []

    public init() {}
}

public struct ImportResult: Equatable, Sendable {
    public let imported: Int
    public let newWallets: Int
    public let newCategories: Int

    public init(imported: Int, newWallets: Int, newCategories: Int) {
        self.imported = imported
        self.newWallets = newWallets
        self.newCategories = newCategories
    }
}

/// Imports the transaction CSV this app exports.
///
/// Import only **adds** transactions; it never changes or deletes existing
/// ones. Wallets and categories are matched by name (ignoring case and
/// accents); missing ones are created (wallets as "Other" with no opening
/// balance). Every row goes through the same rules as manual entry, and the
/// whole import is committed by one save: all rows or none.
public struct ImportService {
    private let context: ModelContext
    private let calendar: CalendarPolicy
    private let now: () -> Date
    private let transactions: TransactionService

    public init(context: ModelContext, calendar: CalendarPolicy = CalendarPolicy(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.calendar = calendar
        self.now = now
        self.transactions = TransactionService(context: context, calendar: calendar, now: now)
    }

    // MARK: Plan

    public func plan(_ parsed: ParsedImport) throws -> ImportPlan {
        var plan = ImportPlan()
        plan.issues = parsed.issues
        let directory = try Directory(context: context)

        let existing = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let existingIDs = Set(existing.map(\.id))
        var signatures = Set<String>()
        for transaction in existing {
            guard let kind = transaction.kind else { continue }
            let main = kind == .income
                ? transaction.entries.first { $0.amountMinorUnits > 0 }
                : transaction.entries.first { $0.amountMinorUnits < 0 }
            if let main, let wallet = main.wallet {
                signatures.insert(Self.signature(kind, transaction.dayKey, wallet.id, main.amountMinorUnits.magnitude))
            }
        }

        var seenIDs = Set<UUID>()
        var newWalletCurrency: [String: CurrencyDefinition] = [:]
        var newCategoryKeys = Set<String>()

        for row in parsed.rows {
            if let id = row.id {
                guard !existingIDs.contains(id), seenIDs.insert(id).inserted else {
                    plan.alreadyImported += 1
                    continue
                }
            }

            var pendingWallets: [ImportPlan.NewWallet] = []
            var pendingCategory: ImportPlan.NewCategory?

            /// Existing wallet, or a wallet this import will create.
            func resolveWallet(_ name: String, currency: CurrencyDefinition) throws -> (wallet: Wallet?, currency: CurrencyDefinition) {
                if let wallet = directory.wallet(named: name) {
                    guard !wallet.isArchived else { throw ImportProblemThrow(.archivedWallet(wallet.name)) }
                    guard let walletCurrency = wallet.currency else { throw ImportProblemThrow(.rejected(.corruptRecord)) }
                    return (wallet, walletCurrency)
                }
                let key = TransactionCSVParser.key(name)
                if let planned = newWalletCurrency[key] ?? pendingWallets.first(where: { TransactionCSVParser.key($0.name) == key })?.currency {
                    return (nil, planned)
                }
                pendingWallets.append(.init(name: name, currency: currency))
                return (nil, currency)
            }

            do {
                let source = try resolveWallet(row.walletName, currency: row.amount.currency)
                guard source.currency == row.amount.currency else {
                    throw ImportProblemThrow(.walletCurrencyMismatch(wallet: row.walletName, currency: row.amount.currency.code))
                }

                switch row.kind {
                case .transfer:
                    let destinationName = row.destinationName ?? ""
                    let destination = try resolveWallet(destinationName, currency: row.received?.currency ?? row.amount.currency)
                    if let received = row.received, received.currency != destination.currency {
                        throw ImportProblemThrow(.walletCurrencyMismatch(wallet: destinationName, currency: received.currency.code))
                    }
                    let received = row.received ?? (destination.currency == source.currency ? row.amount : nil)
                    guard let received else { throw ImportProblemThrow(.rejected(.missingReceivedAmount)) }
                    try LedgerRules.validateTransfer(TransferCandidate(
                        sent: row.amount, received: received,
                        sourceCurrency: source.currency, destinationCurrency: destination.currency,
                        isSameWallet: source.wallet != nil && source.wallet?.id == destination.wallet?.id,
                        sourceIsArchived: false, destinationIsArchived: false
                    ))
                case .income, .expense:
                    guard let type = row.kind.requiredCategoryType, let path = row.categoryPath else {
                        throw ImportProblemThrow(.missingCategory)
                    }
                    if let category = directory.category(path: path, type: type) {
                        guard !category.isArchived else { throw ImportProblemThrow(.archivedCategory(category.name)) }
                    } else {
                        pendingCategory = .init(path: path, type: type)
                    }
                    try LedgerRules.validateCashFlow(CashFlowCandidate(
                        kind: row.kind, amount: row.amount, walletCurrency: source.currency,
                        walletIsArchived: false, categoryType: type, categoryIsArchived: false,
                        keepsExistingCategory: false
                    ))
                }

                if let wallet = source.wallet,
                   signatures.contains(Self.signature(row.kind, calendar.dayKey(for: row.date).rawValue, wallet.id, row.amount.minorUnits.magnitude)) {
                    plan.possibleDuplicates.append(row)
                } else {
                    plan.ready.append(row)
                }
            } catch let problem as ImportProblemThrow {
                plan.issues.append(ImportIssue(line: row.line, problem: problem.problem))
                continue
            } catch let error as LedgerValidationError {
                plan.issues.append(ImportIssue(line: row.line, problem: .rejected(error)))
                continue
            }

            // Only rows that will import create wallets and categories.
            for wallet in pendingWallets {
                newWalletCurrency[TransactionCSVParser.key(wallet.name)] = wallet.currency
                plan.newWallets.append(wallet)
            }
            if let category = pendingCategory,
               newCategoryKeys.insert(category.type.rawValue + "|" + TransactionCSVParser.key(category.path)).inserted {
                plan.newCategories.append(category)
            }
        }
        plan.issues.sort { $0.line < $1.line }
        return plan
    }

    // MARK: Commit

    /// Imports `plan.ready` (and the possible duplicates when asked), creating
    /// missing wallets and categories. One save; on any error nothing is kept.
    @discardableResult
    public func commit(_ plan: ImportPlan, includePossibleDuplicates: Bool = false) throws -> ImportResult {
        let rows = plan.ready + (includePossibleDuplicates ? plan.possibleDuplicates : [])
        var directory = try Directory(context: context)
        var createdWallets = 0
        var createdCategories = 0

        func wallet(_ name: String, currency: CurrencyDefinition) throws -> Wallet {
            if let existing = directory.wallet(named: name) { return existing }
            let wallet = Wallet(
                name: try TextRules.normalizedName(name), type: .other, currency: currency,
                iconName: "wallet.pass", colorIdentifier: "gray",
                sortOrder: directory.nextWalletOrder(), createdAt: now()
            )
            context.insert(wallet)
            directory.add(wallet)
            createdWallets += 1
            return wallet
        }

        func makeCategory(_ name: String, type: CategoryType, parent: LedgerCategory?) throws -> LedgerCategory {
            let category = LedgerCategory(
                name: try TextRules.normalizedName(name), type: type, iconName: "tag", colorIdentifier: "gray",
                sortOrder: directory.nextCategoryOrder(), createdAt: now()
            )
            context.insert(category)
            category.parent = parent
            directory.add(category)
            createdCategories += 1
            return category
        }

        func category(_ path: String, type: CategoryType) throws -> LedgerCategory {
            if let existing = directory.category(path: path, type: type) { return existing }
            let (parentName, name) = Directory.split(path)
            var parent: LedgerCategory?
            if let parentName {
                if let existing = directory.category(path: parentName, type: type) {
                    parent = existing
                } else {
                    parent = try makeCategory(parentName, type: type, parent: nil)
                }
            }
            return try makeCategory(name, type: type, parent: parent)
        }

        do {
            for row in rows {
                let source = try wallet(row.walletName, currency: row.amount.currency)
                let transaction: LedgerTransaction
                switch row.kind {
                case .transfer:
                    let destination = try wallet(row.destinationName ?? "", currency: row.received?.currency ?? row.amount.currency)
                    transaction = try transactions.insertTransfer(TransferDraft(
                        source: source, destination: destination, sent: row.amount, received: row.received,
                        date: row.date, note: row.note
                    ))
                case .income, .expense:
                    guard let type = row.kind.requiredCategoryType, let path = row.categoryPath else {
                        throw LedgerValidationError.missingCategory
                    }
                    transaction = try transactions.insertCashFlow(CashFlowDraft(
                        kind: row.kind, amount: row.amount, wallet: source,
                        category: try category(path, type: type),
                        date: row.date, note: row.note, merchant: row.merchant
                    ))
                }
                if let id = row.id { transaction.id = id }
            }
            try context.saveOrRollback()
        } catch {
            context.rollback()
            throw error
        }
        return ImportResult(imported: rows.count, newWallets: createdWallets, newCategories: createdCategories)
    }

    // MARK: Private

    private static func signature(_ kind: TransactionKind, _ dayKey: Int, _ walletID: UUID, _ magnitude: UInt64) -> String {
        "\(kind.rawValue)|\(dayKey)|\(walletID.uuidString)|\(magnitude)"
    }

    private struct ImportProblemThrow: Error {
        let problem: ImportProblem
        init(_ problem: ImportProblem) { self.problem = problem }
    }

    /// Wallets and categories looked up by name (case- and accent-insensitive).
    /// Active records win over archived ones with the same name.
    private struct Directory {
        private var wallets: [String: Wallet] = [:]
        private var categories: [LedgerCategory]
        private var maxWalletOrder: Int
        private var maxCategoryOrder: Int

        init(context: ModelContext) throws {
            let allWallets = try context.fetch(FetchDescriptor<Wallet>())
            for wallet in allWallets.sorted(by: { !$0.isArchived && $1.isArchived }) {
                let key = TransactionCSVParser.key(wallet.name)
                if wallets[key] == nil { wallets[key] = wallet }
            }
            categories = try context.fetch(FetchDescriptor<LedgerCategory>())
                .sorted { !$0.isArchived && $1.isArchived }
            maxWalletOrder = allWallets.map(\.sortOrder).max() ?? -1
            maxCategoryOrder = categories.map(\.sortOrder).max() ?? -1
        }

        func wallet(named name: String) -> Wallet? {
            wallets[TransactionCSVParser.key(name)]
        }

        /// "Food / Coffee" matches the child Coffee under Food; "Coffee" prefers a top-level match.
        func category(path: String, type: CategoryType) -> LedgerCategory? {
            let (parentName, name) = Self.split(path)
            let key = TransactionCSVParser.key(name)
            let candidates = categories.filter { $0.type == type && TransactionCSVParser.key($0.name) == key }
            if let parentName {
                let parentKey = TransactionCSVParser.key(parentName)
                return candidates.first { $0.parent.map { TransactionCSVParser.key($0.name) == parentKey } ?? false }
            }
            return candidates.first { $0.parent == nil } ?? candidates.first
        }

        static func split(_ path: String) -> (parent: String?, name: String) {
            let parts = path.components(separatedBy: " / ")
            guard parts.count >= 2 else { return (nil, path) }
            return (parts[0], parts.dropFirst().joined(separator: " / "))
        }

        mutating func add(_ wallet: Wallet) {
            wallets[TransactionCSVParser.key(wallet.name)] = wallet
            maxWalletOrder = max(maxWalletOrder, wallet.sortOrder)
        }

        mutating func add(_ category: LedgerCategory) {
            categories.insert(category, at: 0)
            maxCategoryOrder = max(maxCategoryOrder, category.sortOrder)
        }

        func nextWalletOrder() -> Int { maxWalletOrder + 1 }
        func nextCategoryOrder() -> Int { maxCategoryOrder + 1 }
    }
}
