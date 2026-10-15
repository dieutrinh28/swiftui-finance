import Foundation

/// Checks a whole backup before anything in the store is touched.
///
/// The same invariants the services enforce on every write are checked here,
/// so a restored store is as consistent as one built through the app:
/// unique ids, known enum values and currencies, every reference resolvable,
/// and every transaction balanced (income one positive entry, expense one
/// negative entry, transfer one out and one in between two wallets).
public enum BackupValidator {
    @discardableResult
    public static func validate(_ document: BackupDocument) throws -> BackupSummary {
        guard document.format == BackupDocument.formatIdentifier else { throw BackupError.notABackup }
        guard document.formatVersion <= BackupDocument.currentFormatVersion else {
            throw BackupError.newerFormat(version: document.formatVersion)
        }

        // Wallets
        try requireUnique(document.wallets.map(\.id), entity: "wallet")
        var walletCurrency: [UUID: String] = [:]
        for wallet in document.wallets {
            guard WalletType(rawValue: wallet.type) != nil else {
                throw BackupError.invalidValue(field: "wallet type", value: wallet.type)
            }
            try requireCurrency(wallet.currencyCode)
            walletCurrency[wallet.id] = wallet.currencyCode.uppercased()
        }

        // Categories
        try requireUnique(document.categories.map(\.id), entity: "category")
        let categoryIDs = Set(document.categories.map(\.id))
        var parentOf: [UUID: UUID] = [:]
        for category in document.categories {
            guard CategoryType(rawValue: category.type) != nil else {
                throw BackupError.invalidValue(field: "category type", value: category.type)
            }
            if let parent = category.parentID {
                guard categoryIDs.contains(parent) else {
                    throw BackupError.missingReference(entity: "category", id: parent)
                }
                parentOf[category.id] = parent
            }
        }
        for start in categoryIDs {
            var seen: Set<UUID> = [start]
            var current = parentOf[start]
            while let id = current {
                guard seen.insert(id).inserted else { throw BackupError.categoryCycle }
                current = parentOf[id]
            }
        }

        // Transactions
        try requireUnique(document.transactions.map(\.id), entity: "transaction")
        try requireUnique(document.transactions.flatMap { $0.entries.map(\.id) }, entity: "entry")
        for transaction in document.transactions {
            try validate(transaction, walletCurrency: walletCurrency, categoryIDs: categoryIDs)
        }

        // Budgets
        try requireUnique(document.budgets.map(\.id), entity: "budget")
        for budget in document.budgets {
            guard BudgetPeriod(rawValue: budget.period) != nil else {
                throw BackupError.invalidValue(field: "budget period", value: budget.period)
            }
            try requireCurrency(budget.currencyCode)
            guard budget.plannedAmountMinorUnits > 0 else {
                throw BackupError.invalidValue(field: "budget amount", value: String(budget.plannedAmountMinorUnits))
            }
            for id in budget.categoryIDs where !categoryIDs.contains(id) {
                throw BackupError.missingReference(entity: "category", id: id)
            }
            for id in budget.walletIDs where walletCurrency[id] == nil {
                throw BackupError.missingReference(entity: "wallet", id: id)
            }
            guard (try? BudgetAlertRules.normalizedThresholds(budget.alertThresholdPercents)) != nil else {
                throw BackupError.invalidValue(field: "alert thresholds",
                                               value: budget.alertThresholdPercents.map(String.init).joined(separator: ","))
            }
        }

        // Savings goals
        try requireUnique(document.savingsGoals.map(\.id), entity: "savings goal")
        try requireUnique(document.savingsGoals.flatMap { $0.contributions.map(\.id) }, entity: "contribution")
        for goal in document.savingsGoals {
            try requireCurrency(goal.currencyCode)
            guard goal.targetAmountMinorUnits > 0 else {
                throw BackupError.invalidValue(field: "goal target", value: String(goal.targetAmountMinorUnits))
            }
            if let wallet = goal.linkedWalletID, walletCurrency[wallet] == nil {
                throw BackupError.missingReference(entity: "wallet", id: wallet)
            }
            let saved = goal.contributions.reduce(Int64(0)) { $0 + $1.amountMinorUnits }
            guard saved >= 0 else {
                throw BackupError.invalidValue(field: "goal saved amount", value: String(saved))
            }
        }

        // Recurring
        try requireUnique(document.recurring.map(\.id), entity: "recurring transaction")
        for item in document.recurring {
            guard let kind = TransactionKind(rawValue: item.kind) else {
                throw BackupError.invalidValue(field: "recurring kind", value: item.kind)
            }
            guard RecurrenceFrequency(rawValue: item.frequency) != nil else {
                throw BackupError.invalidValue(field: "frequency", value: item.frequency)
            }
            guard RecurrenceRules.intervalRange.contains(item.interval) else {
                throw BackupError.invalidValue(field: "interval", value: String(item.interval))
            }
            guard item.amountMinorUnits > 0 else {
                throw BackupError.invalidValue(field: "recurring amount", value: String(item.amountMinorUnits))
            }
            guard let currency = walletCurrency[item.walletID] else {
                throw BackupError.missingReference(entity: "wallet", id: item.walletID)
            }
            guard currency == item.currencyCode.uppercased() else {
                throw BackupError.invalidValue(field: "recurring currency", value: item.currencyCode)
            }
            if kind == .transfer {
                guard let destination = item.destinationWalletID, let destinationCurrency = walletCurrency[destination] else {
                    throw BackupError.missingReference(entity: "wallet", id: item.destinationWalletID ?? item.walletID)
                }
                guard destination != item.walletID else {
                    throw BackupError.invalidValue(field: "recurring destination", value: destination.uuidString)
                }
                if destinationCurrency == currency {
                    guard item.receivedAmountMinorUnits == nil || item.receivedAmountMinorUnits == item.amountMinorUnits else {
                        throw BackupError.invalidValue(field: "recurring received amount",
                                                       value: String(item.receivedAmountMinorUnits ?? 0))
                    }
                } else if let received = item.receivedAmountMinorUnits, received <= 0 {
                    throw BackupError.invalidValue(field: "recurring received amount", value: String(received))
                }
            } else {
                guard let category = item.categoryID else {
                    throw BackupError.invalidValue(field: "recurring category", value: "")
                }
                guard categoryIDs.contains(category) else {
                    throw BackupError.missingReference(entity: "category", id: category)
                }
            }
        }

        return BackupSummary(
            exportedAt: document.exportedAt,
            wallets: document.wallets.count,
            categories: document.categories.count,
            transactions: document.transactions.count,
            budgets: document.budgets.count,
            savingsGoals: document.savingsGoals.count,
            recurring: document.recurring.count
        )
    }

    // MARK: Private

    private static func validate(
        _ transaction: BackupDocument.TransactionRecord,
        walletCurrency: [UUID: String],
        categoryIDs: Set<UUID>
    ) throws {
        guard let kind = TransactionKind(rawValue: transaction.kind) else {
            throw BackupError.invalidValue(field: "transaction kind", value: transaction.kind)
        }
        if let category = transaction.categoryID, !categoryIDs.contains(category) {
            throw BackupError.missingReference(entity: "category", id: category)
        }
        for entry in transaction.entries {
            guard let currency = walletCurrency[entry.walletID] else {
                throw BackupError.missingReference(entity: "wallet", id: entry.walletID)
            }
            guard currency == entry.currencyCode.uppercased(), entry.amountMinorUnits != 0 else {
                throw BackupError.invalidTransaction(id: transaction.id)
            }
        }

        let entries = transaction.entries
        let balanced: Bool
        switch kind {
        case .income:
            balanced = entries.count == 1 && entries[0].amountMinorUnits > 0 && transaction.categoryID != nil
        case .expense:
            balanced = entries.count == 1 && entries[0].amountMinorUnits < 0 && transaction.categoryID != nil
        case .transfer:
            guard entries.count == 2,
                  let outgoing = entries.first(where: { $0.amountMinorUnits < 0 }),
                  let incoming = entries.first(where: { $0.amountMinorUnits > 0 }),
                  outgoing.walletID != incoming.walletID
            else {
                balanced = false
                break
            }
            // Same currency: what leaves one wallet arrives in the other.
            balanced = outgoing.currencyCode.uppercased() != incoming.currencyCode.uppercased()
                || outgoing.amountMinorUnits == -incoming.amountMinorUnits
        }
        guard balanced else { throw BackupError.invalidTransaction(id: transaction.id) }
    }

    private static func requireUnique(_ ids: [UUID], entity: String) throws {
        guard Set(ids).count == ids.count else { throw BackupError.duplicateID(entity: entity) }
    }

    private static func requireCurrency(_ code: String) throws {
        guard CurrencyCatalog.isSupported(code) else {
            throw BackupError.invalidValue(field: "currency", value: code)
        }
    }
}
