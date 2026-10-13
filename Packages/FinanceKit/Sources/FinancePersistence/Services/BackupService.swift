import Foundation
import SwiftData
import FinanceDomain

/// Full backups and restores of the store.
///
/// Restore is all-or-nothing: the backup is validated completely before the
/// store is touched, then every existing record is deleted and every record
/// from the backup inserted on the same context, and the whole change is
/// committed by one `save()` (one SQLite transaction). If anything fails, the
/// context is rolled back and the store is exactly as before.
public struct BackupService {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    // MARK: Backup

    public func makeBackup() throws -> BackupDocument {
        let wallets = try context.fetch(FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\.sortOrder)]))
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date)]))
        let budgets = try context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.sortOrder)]))
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>(sortBy: [SortDescriptor(\.sortOrder)]))
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>(sortBy: [SortDescriptor(\.sortOrder)]))

        return BackupDocument(
            schemaVersion: ModelContainerFactory.currentSchemaVersion,
            exportedAt: now(),
            wallets: wallets.map {
                .init(id: $0.id, name: $0.name, type: $0.typeRaw, currencyCode: $0.currencyCode,
                      openingBalanceMinorUnits: $0.openingBalanceMinorUnits, iconName: $0.iconName,
                      colorIdentifier: $0.colorIdentifier, note: $0.note, sortOrder: $0.sortOrder,
                      createdAt: $0.createdAt, updatedAt: $0.updatedAt, archivedAt: $0.archivedAt)
            },
            categories: categories.map {
                .init(id: $0.id, name: $0.name, type: $0.typeRaw, iconName: $0.iconName,
                      colorIdentifier: $0.colorIdentifier, seedKey: $0.seedKey, parentID: $0.parent?.id,
                      sortOrder: $0.sortOrder, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                      archivedAt: $0.archivedAt)
            },
            transactions: try transactions.map { transaction in
                let entries = try transaction.entries
                    .sorted { $0.amountMinorUnits < $1.amountMinorUnits }
                    .map { entry -> BackupDocument.EntryRecord in
                        guard let wallet = entry.wallet else { throw LedgerValidationError.corruptRecord }
                        return .init(id: entry.id, walletID: wallet.id,
                                     amountMinorUnits: entry.amountMinorUnits, currencyCode: entry.currencyCode)
                    }
                return .init(id: transaction.id, kind: transaction.kindRaw, date: transaction.date,
                             dayKey: transaction.dayKey, categoryID: transaction.category?.id,
                             note: transaction.note, merchant: transaction.merchant,
                             exchangeRateText: transaction.exchangeRateText,
                             recurringOccurrenceKey: transaction.recurringOccurrenceKey,
                             createdAt: transaction.createdAt, updatedAt: transaction.updatedAt, entries: entries)
            },
            budgets: budgets.map {
                .init(id: $0.id, name: $0.name, plannedAmountMinorUnits: $0.plannedAmountMinorUnits,
                      currencyCode: $0.currencyCode, period: $0.periodRaw, startDate: $0.startDate,
                      endDate: $0.endDate, categoryIDs: $0.categoryIDs, walletIDs: $0.walletIDs,
                      rolloverEnabled: $0.rolloverEnabled, alertThresholdPercents: $0.alertThresholdPercents,
                      sortOrder: $0.sortOrder, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                      archivedAt: $0.archivedAt)
            },
            savingsGoals: goals.map { goal in
                .init(id: goal.id, name: goal.name, targetAmountMinorUnits: goal.targetAmountMinorUnits,
                      currencyCode: goal.currencyCode, targetDate: goal.targetDate,
                      linkedWalletID: goal.linkedWalletID, note: goal.note, iconName: goal.iconName,
                      colorIdentifier: goal.colorIdentifier, sortOrder: goal.sortOrder,
                      createdAt: goal.createdAt, updatedAt: goal.updatedAt, completedAt: goal.completedAt,
                      archivedAt: goal.archivedAt,
                      contributions: goal.contributionsNewestFirst.reversed().map {
                          .init(id: $0.id, amountMinorUnits: $0.amountMinorUnits, date: $0.date,
                                dayKey: $0.dayKey, note: $0.note, createdAt: $0.createdAt)
                      })
            },
            recurring: recurring.map {
                .init(id: $0.id, name: $0.name, kind: $0.kindRaw, amountMinorUnits: $0.amountMinorUnits,
                      currencyCode: $0.currencyCode, walletID: $0.walletID, categoryID: $0.categoryID,
                      frequency: $0.frequencyRaw, interval: $0.interval, startDate: $0.startDate,
                      endDate: $0.endDate, note: $0.note, reminderEnabled: $0.reminderEnabled,
                      reminderMinutes: $0.reminderMinutes, pausedAt: $0.pausedAt,
                      handledOccurrenceKeys: $0.handledOccurrenceKeys, sortOrder: $0.sortOrder,
                      createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            }
        )
    }

    /// True when there is nothing worth protecting before a restore
    /// (no wallets and no transactions; default categories don't count).
    public func hasUserData() throws -> Bool {
        try context.fetchCount(FetchDescriptor<Wallet>()) > 0
            || context.fetchCount(FetchDescriptor<LedgerTransaction>()) > 0
    }

    // MARK: Restore

    /// Replaces every record in the store with the backup's records.
    @discardableResult
    public func restore(_ document: BackupDocument) throws -> BackupSummary {
        let summary = try BackupValidator.validate(document)
        do {
            try deleteEverything()
            try insert(document)
            try context.saveOrRollback()
        } catch {
            context.rollback()
            throw error
        }
        return summary
    }

    // MARK: Private

    private func deleteEverything() throws {
        // Detach first so `.deny` rules never see a half-deleted graph.
        for entry in try context.fetch(FetchDescriptor<LedgerEntry>()) {
            entry.wallet = nil
            entry.transaction = nil
            context.delete(entry)
        }
        for transaction in try context.fetch(FetchDescriptor<LedgerTransaction>()) {
            transaction.category = nil
            context.delete(transaction)
        }
        for contribution in try context.fetch(FetchDescriptor<SavingsContribution>()) {
            contribution.goal = nil
            context.delete(contribution)
        }
        for goal in try context.fetch(FetchDescriptor<SavingsGoal>()) { context.delete(goal) }
        for item in try context.fetch(FetchDescriptor<RecurringTransaction>()) { context.delete(item) }
        for budget in try context.fetch(FetchDescriptor<Budget>()) { context.delete(budget) }
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        for category in categories { category.parent = nil }
        for category in categories { context.delete(category) }
        for wallet in try context.fetch(FetchDescriptor<Wallet>()) { context.delete(wallet) }
    }

    private func insert(_ document: BackupDocument) throws {
        var wallets: [UUID: Wallet] = [:]
        for record in document.wallets {
            guard let type = WalletType(rawValue: record.type) else { throw BackupError.invalidValue(field: "wallet type", value: record.type) }
            let wallet = Wallet(
                id: record.id, name: record.name, type: type,
                currency: try CurrencyCatalog.definition(for: record.currencyCode),
                openingBalanceMinorUnits: record.openingBalanceMinorUnits,
                iconName: record.iconName, colorIdentifier: record.colorIdentifier, note: record.note,
                sortOrder: record.sortOrder, createdAt: record.createdAt
            )
            wallet.updatedAt = record.updatedAt
            wallet.archivedAt = record.archivedAt
            context.insert(wallet)
            wallets[record.id] = wallet
        }

        var categories: [UUID: LedgerCategory] = [:]
        for record in document.categories {
            guard let type = CategoryType(rawValue: record.type) else { throw BackupError.invalidValue(field: "category type", value: record.type) }
            let category = LedgerCategory(
                id: record.id, name: record.name, type: type, iconName: record.iconName,
                colorIdentifier: record.colorIdentifier, seedKey: record.seedKey,
                sortOrder: record.sortOrder, createdAt: record.createdAt
            )
            category.updatedAt = record.updatedAt
            category.archivedAt = record.archivedAt
            context.insert(category)
            categories[record.id] = category
        }
        for record in document.categories {
            if let parentID = record.parentID { categories[record.id]?.parent = categories[parentID] }
        }

        for record in document.transactions {
            guard let kind = TransactionKind(rawValue: record.kind) else { throw BackupError.invalidTransaction(id: record.id) }
            let transaction = LedgerTransaction(
                id: record.id, kind: kind, date: record.date, dayKey: DayKey(rawValue: record.dayKey),
                note: record.note, merchant: record.merchant, createdAt: record.createdAt
            )
            transaction.exchangeRateText = record.exchangeRateText
            transaction.recurringOccurrenceKey = record.recurringOccurrenceKey
            transaction.updatedAt = record.updatedAt
            context.insert(transaction)
            transaction.category = record.categoryID.flatMap { categories[$0] }
            for entryRecord in record.entries {
                guard let wallet = wallets[entryRecord.walletID] else {
                    throw BackupError.missingReference(entity: "wallet", id: entryRecord.walletID)
                }
                let entry = LedgerEntry(id: entryRecord.id, amountMinorUnits: entryRecord.amountMinorUnits,
                                        currencyCode: entryRecord.currencyCode.uppercased())
                context.insert(entry)
                entry.wallet = wallet
                entry.transaction = transaction
            }
        }

        for record in document.budgets {
            guard let period = BudgetPeriod(rawValue: record.period) else { throw BackupError.invalidValue(field: "budget period", value: record.period) }
            let budget = Budget(
                id: record.id, name: record.name,
                planned: Money(minorUnits: record.plannedAmountMinorUnits,
                               currency: try CurrencyCatalog.definition(for: record.currencyCode)),
                period: period, startDate: record.startDate, endDate: record.endDate,
                categoryIDs: record.categoryIDs, walletIDs: record.walletIDs,
                rolloverEnabled: record.rolloverEnabled, alertThresholdPercents: record.alertThresholdPercents,
                sortOrder: record.sortOrder, createdAt: record.createdAt
            )
            budget.updatedAt = record.updatedAt
            budget.archivedAt = record.archivedAt
            context.insert(budget)
        }

        for record in document.savingsGoals {
            let goal = SavingsGoal(
                id: record.id, name: record.name,
                target: Money(minorUnits: record.targetAmountMinorUnits,
                              currency: try CurrencyCatalog.definition(for: record.currencyCode)),
                targetDate: record.targetDate, linkedWalletID: record.linkedWalletID, note: record.note,
                iconName: record.iconName, colorIdentifier: record.colorIdentifier,
                sortOrder: record.sortOrder, createdAt: record.createdAt
            )
            goal.updatedAt = record.updatedAt
            goal.completedAt = record.completedAt
            goal.archivedAt = record.archivedAt
            context.insert(goal)
            for contributionRecord in record.contributions {
                let contribution = SavingsContribution(
                    id: contributionRecord.id, amountMinorUnits: contributionRecord.amountMinorUnits,
                    date: contributionRecord.date, dayKey: DayKey(rawValue: contributionRecord.dayKey),
                    note: contributionRecord.note, createdAt: contributionRecord.createdAt
                )
                context.insert(contribution)
                contribution.goal = goal
            }
        }

        for record in document.recurring {
            guard let kind = TransactionKind(rawValue: record.kind),
                  let frequency = RecurrenceFrequency(rawValue: record.frequency)
            else { throw BackupError.invalidValue(field: "recurring", value: record.kind) }
            let item = RecurringTransaction(
                id: record.id, name: record.name, kind: kind,
                amount: Money(minorUnits: record.amountMinorUnits,
                              currency: try CurrencyCatalog.definition(for: record.currencyCode)),
                walletID: record.walletID, categoryID: record.categoryID,
                schedule: RecurrenceSchedule(frequency: frequency, interval: record.interval,
                                             startDate: record.startDate, endDate: record.endDate),
                note: record.note, reminderEnabled: record.reminderEnabled,
                reminderMinutes: record.reminderMinutes, sortOrder: record.sortOrder, createdAt: record.createdAt
            )
            item.pausedAt = record.pausedAt
            item.handledOccurrenceKeys = record.handledOccurrenceKeys
            item.updatedAt = record.updatedAt
            context.insert(item)
        }
    }
}
