import Foundation

/// A financial operation was rejected before anything was written.
public enum LedgerValidationError: Error, Equatable, Sendable {
    case emptyName
    case nonPositiveAmount
    case negativeAmount
    case currencyMismatch(walletCurrency: String, amountCurrency: String)
    case missingCategory
    case categoryTypeMismatch(required: CategoryType, actual: CategoryType)
    case transfersNotSupported
    case archivedWallet
    case archivedCategory
    case walletCurrencyLocked
    case walletHasHistory
    case categoryHasHistory
    case categoryTypeLocked
    case corruptRecord
    case sameWalletTransfer
    case missingDestinationWallet
    case missingReceivedAmount
    case transferAmountsDiffer
    case budgetNeedsCategories
    case budgetNeedsEndDate
    case categoryUsedByBudget
    case walletUsedByBudget
    case invalidRecurrence
    case duplicateOccurrence
    case withdrawalExceedsSavings
    case walletUsedByRecurring
    case categoryUsedByRecurring
    case walletUsedBySavingsGoal
    case goalCurrencyLocked
}

extension LedgerValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName:
            "Please enter a name."
        case .nonPositiveAmount:
            "The amount must be greater than zero."
        case .negativeAmount:
            "The amount can't be negative."
        case .currencyMismatch(let walletCurrency, let amountCurrency):
            "This wallet uses \(walletCurrency), but the amount is in \(amountCurrency)."
        case .missingCategory:
            "Please choose a category."
        case .categoryTypeMismatch(let required, _):
            required == .expense
                ? "Expenses need an expense category."
                : "Income needs an income category."
        case .transfersNotSupported:
            "Transfers between wallets are not available yet."
        case .archivedWallet:
            "This wallet is archived. Restore it before adding or changing its transactions."
        case .archivedCategory:
            "This category is archived. Restore it or choose another category."
        case .walletCurrencyLocked:
            "The currency can't be changed because this wallet already has transactions."
        case .walletHasHistory:
            "This wallet has transactions, so it can't be deleted. Archive it instead to keep its history."
        case .categoryHasHistory:
            "This category is used by transactions, so it can't be deleted. Archive it instead."
        case .categoryTypeLocked:
            "This category is used by transactions, so it can't switch between income and expense."
        case .corruptRecord:
            "This record contains data the app doesn't recognise. Nothing was changed."
        case .sameWalletTransfer:
            "Choose two different wallets for a transfer."
        case .missingDestinationWallet:
            "Please choose the wallet that receives the money."
        case .missingReceivedAmount:
            "These wallets use different currencies. Enter the amount that arrives in the destination wallet."
        case .transferAmountsDiffer:
            "Both wallets use the same currency, so the amount sent and received must be equal."
        case .budgetNeedsCategories:
            "Choose at least one expense category for this budget."
        case .budgetNeedsEndDate:
            "A custom budget needs an end date."
        case .categoryUsedByBudget:
            "This category is part of a budget. Remove it from the budget or archive the category instead."
        case .walletUsedByBudget:
            "A budget is limited to this wallet. Change that budget first, or archive the wallet."
        case .invalidRecurrence:
            "Repeat every 1 to 365 days, weeks, months or years, and end on or after the start date."
        case .duplicateOccurrence:
            "This occurrence has already been recorded."
        case .withdrawalExceedsSavings:
            "You can't take out more than has been saved for this goal."
        case .walletUsedByRecurring:
            "A recurring transaction uses this wallet. Change or delete it first, or archive the wallet."
        case .categoryUsedByRecurring:
            "A recurring transaction uses this category. Change or delete it first, or archive the category."
        case .walletUsedBySavingsGoal:
            "A savings goal is linked to this wallet. Unlink it first, or archive the wallet."
        case .goalCurrencyLocked:
            "The currency can't be changed because this goal already has contributions."
        }
    }
}
