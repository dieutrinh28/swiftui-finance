import Foundation
import SwiftData
import FinanceDomain

/// Input for creating or editing a wallet.
public struct WalletDraft: Sendable, Equatable {
    public var name: String
    public var type: WalletType
    public var currency: CurrencyDefinition
    /// Non-negative: money held (assets) or amount currently owed (liabilities).
    public var enteredOpeningBalance: Money
    public var iconName: String
    public var colorIdentifier: String
    public var note: String?

    public init(
        name: String,
        type: WalletType,
        currency: CurrencyDefinition,
        enteredOpeningBalance: Money,
        iconName: String,
        colorIdentifier: String,
        note: String? = nil
    ) {
        self.name = name
        self.type = type
        self.currency = currency
        self.enteredOpeningBalance = enteredOpeningBalance
        self.iconName = iconName
        self.colorIdentifier = colorIdentifier
        self.note = note
    }
}

/// All wallet mutations. Each public method validates first, then writes,
/// then saves once. On any failure the context is rolled back.
public struct WalletService {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    @discardableResult
    public func create(_ draft: WalletDraft) throws -> Wallet {
        let name = try TextRules.normalizedName(draft.name)
        let opening = try storedOpening(for: draft)
        let wallet = Wallet(
            name: name,
            type: draft.type,
            currency: draft.currency,
            openingBalanceMinorUnits: opening.minorUnits,
            iconName: draft.iconName,
            colorIdentifier: draft.colorIdentifier,
            note: TextRules.optionalText(draft.note),
            sortOrder: try nextSortOrder(),
            createdAt: now()
        )
        context.insert(wallet)
        try context.saveOrRollback()
        return wallet
    }

    public func update(_ wallet: Wallet, with draft: WalletDraft) throws {
        guard !wallet.isArchived else { throw LedgerValidationError.archivedWallet }
        let name = try TextRules.normalizedName(draft.name)
        let opening = try storedOpening(for: draft)
        if draft.currency.code != wallet.currencyCode {
            if wallet.hasHistory { throw LedgerValidationError.walletCurrencyLocked }
            // Recurring items store the wallet's currency, budgets limited to a
            // wallet and goals linked to it must share it (I7 in ARCHITECTURE.md).
            if try RecurringReferences.isWalletUsed(wallet, in: context)
                || BudgetReferences.isWalletUsed(wallet, in: context)
                || SavingsReferences.isWalletLinked(wallet, in: context) {
                throw LedgerValidationError.walletCurrencyInUse
            }
        }

        wallet.name = name
        wallet.type = draft.type
        wallet.currencyCode = draft.currency.code
        wallet.openingBalanceMinorUnits = opening.minorUnits
        wallet.iconName = draft.iconName
        wallet.colorIdentifier = draft.colorIdentifier
        wallet.note = TextRules.optionalText(draft.note)
        wallet.updatedAt = now()
        try context.saveOrRollback()
    }

    /// Hides the wallet from pickers and lists; its history is kept and it becomes read-only.
    public func archive(_ wallet: Wallet) throws {
        guard !wallet.isArchived else { return }
        let timestamp = now()
        wallet.archivedAt = timestamp
        wallet.updatedAt = timestamp
        try context.saveOrRollback()
    }

    public func restore(_ wallet: Wallet) throws {
        guard wallet.isArchived else { return }
        wallet.archivedAt = nil
        wallet.updatedAt = now()
        try context.saveOrRollback()
    }

    /// Only wallets without transactions and not named by a budget can be deleted.
    public func delete(_ wallet: Wallet) throws {
        guard !wallet.hasHistory else { throw LedgerValidationError.walletHasHistory }
        guard try !BudgetReferences.isWalletUsed(wallet, in: context) else {
            throw LedgerValidationError.walletUsedByBudget
        }
        guard try !RecurringReferences.isWalletUsed(wallet, in: context) else {
            throw LedgerValidationError.walletUsedByRecurring
        }
        guard try !SavingsReferences.isWalletLinked(wallet, in: context) else {
            throw LedgerValidationError.walletUsedBySavingsGoal
        }
        context.delete(wallet)
        try context.saveOrRollback()
    }

    private func storedOpening(for draft: WalletDraft) throws -> Money {
        guard draft.enteredOpeningBalance.currency == draft.currency else {
            throw LedgerValidationError.currencyMismatch(
                walletCurrency: draft.currency.code,
                amountCurrency: draft.enteredOpeningBalance.currency.code
            )
        }
        return try WalletRules.storedOpeningBalance(
            entered: draft.enteredOpeningBalance,
            accountClass: draft.type.accountClass
        )
    }

    private func nextSortOrder() throws -> Int {
        var descriptor = FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortOrder ?? -1) + 1
    }
}
