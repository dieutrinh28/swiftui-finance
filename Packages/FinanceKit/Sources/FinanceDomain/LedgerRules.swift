import Foundation

/// Everything needed to decide whether an income or expense may be recorded.
/// Built from plain values so the rules can be tested without a database.
public struct CashFlowCandidate: Sendable, Equatable {
    public var kind: TransactionKind
    /// Unsigned amount entered by the user.
    public var amount: Money
    public var walletCurrency: CurrencyDefinition
    public var walletIsArchived: Bool
    /// nil when no category was chosen.
    public var categoryType: CategoryType?
    public var categoryIsArchived: Bool
    /// True when editing a transaction that already uses this (now archived)
    /// category: keeping it is allowed, newly choosing it is not.
    public var keepsExistingCategory: Bool

    public init(
        kind: TransactionKind,
        amount: Money,
        walletCurrency: CurrencyDefinition,
        walletIsArchived: Bool = false,
        categoryType: CategoryType?,
        categoryIsArchived: Bool = false,
        keepsExistingCategory: Bool = false
    ) {
        self.kind = kind
        self.amount = amount
        self.walletCurrency = walletCurrency
        self.walletIsArchived = walletIsArchived
        self.categoryType = categoryType
        self.categoryIsArchived = categoryIsArchived
        self.keepsExistingCategory = keepsExistingCategory
    }
}

/// Core ledger invariants. See docs/ARCHITECTURE.md.
public enum LedgerRules {
    /// Validates an income or expense. Order matters: the first broken rule is reported.
    public static func validateCashFlow(_ candidate: CashFlowCandidate) throws {
        guard let requiredCategory = candidate.kind.requiredCategoryType else {
            throw LedgerValidationError.transfersNotSupported
        }
        guard candidate.amount.isPositive else {
            throw LedgerValidationError.nonPositiveAmount
        }
        guard candidate.amount.currency == candidate.walletCurrency else {
            throw LedgerValidationError.currencyMismatch(
                walletCurrency: candidate.walletCurrency.code,
                amountCurrency: candidate.amount.currency.code
            )
        }
        guard !candidate.walletIsArchived else {
            throw LedgerValidationError.archivedWallet
        }
        guard let categoryType = candidate.categoryType else {
            throw LedgerValidationError.missingCategory
        }
        guard categoryType == requiredCategory else {
            throw LedgerValidationError.categoryTypeMismatch(required: requiredCategory, actual: categoryType)
        }
        guard !candidate.categoryIsArchived || candidate.keepsExistingCategory else {
            throw LedgerValidationError.archivedCategory
        }
    }

    /// The signed ledger amount for a cash-flow transaction:
    /// income adds to the wallet, expense subtracts from it.
    public static func signedMinorUnits(for kind: TransactionKind, amount: Money) throws -> Int64 {
        switch kind {
        case .income: amount.minorUnits
        case .expense: try amount.negated().minorUnits
        case .transfer: throw LedgerValidationError.transfersNotSupported
        }
    }

    /// Wallet balance = opening balance + every ledger entry of that wallet.
    /// All values must share the opening balance's currency.
    public static func balance(opening: Money, entries: [Money]) throws -> Money {
        try opening.adding(Money.sum(entries, currency: opening.currency))
    }
}

/// Rules for names and free text shared by wallets and categories.
public enum TextRules {
    public static let maximumNameLength = 60

    /// Trimmed, non-empty, at most `maximumNameLength` characters.
    public static func normalizedName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerValidationError.emptyName }
        return String(trimmed.prefix(maximumNameLength))
    }

    /// Trimmed text, or nil when empty.
    public static func optionalText(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// How the opening balance typed by the user maps to the stored value.
///
/// The user always enters a non-negative amount: the money held in an asset
/// wallet, or the amount currently owed on a liability (credit card). Liabilities
/// are stored negative, following the sign convention of `AccountClass`.
public enum WalletRules {
    public static func storedOpeningBalance(entered: Money, accountClass: AccountClass) throws -> Money {
        guard !entered.isNegative else { throw LedgerValidationError.negativeAmount }
        return accountClass == .liability ? try entered.negated() : entered
    }

    public static func enteredOpeningBalance(stored: Money, accountClass: AccountClass) throws -> Money {
        accountClass == .liability ? try stored.negated() : stored
    }
}
