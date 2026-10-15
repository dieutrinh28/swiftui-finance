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
    /// A recurring item, budget or savings goal relies on the wallet's currency.
    case walletCurrencyInUse
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
    case invalidParentCategory
    case categoryHasSubcategories
    case categoryTypeInUse
    case invalidAlertThresholds
}

extension LedgerValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName:
            String(localized: "Please enter a name.", bundle: .l10n)
        case .nonPositiveAmount:
            String(localized: "The amount must be greater than zero.", bundle: .l10n)
        case .negativeAmount:
            String(localized: "The amount can't be negative.", bundle: .l10n)
        case .currencyMismatch(let walletCurrency, let amountCurrency):
            String(localized: "This wallet uses \(walletCurrency), but the amount is in \(amountCurrency).", bundle: .l10n)
        case .missingCategory:
            String(localized: "Please choose a category.", bundle: .l10n)
        case .categoryTypeMismatch(let required, _):
            required == .expense
                ? String(localized: "Expenses need an expense category.", bundle: .l10n)
                : String(localized: "Income needs an income category.", bundle: .l10n)
        case .transfersNotSupported:
            String(localized: "Transfers between wallets are not available yet.", bundle: .l10n)
        case .archivedWallet:
            String(localized: "This wallet is archived. Restore it before adding or changing its transactions.", bundle: .l10n)
        case .archivedCategory:
            String(localized: "This category is archived. Restore it or choose another category.", bundle: .l10n)
        case .walletCurrencyLocked:
            String(localized: "The currency can't be changed because this wallet already has transactions.", bundle: .l10n)
        case .walletCurrencyInUse:
            String(localized: "The currency can't be changed because a recurring transaction, a budget or a savings goal uses this wallet. Change those first.", bundle: .l10n)
        case .walletHasHistory:
            String(localized: "This wallet has transactions, so it can't be deleted. Archive it instead to keep its history.", bundle: .l10n)
        case .categoryHasHistory:
            String(localized: "This category is used by transactions, so it can't be deleted. Archive it instead.", bundle: .l10n)
        case .categoryTypeLocked:
            String(localized: "This category is used by transactions, so it can't switch between income and expense.", bundle: .l10n)
        case .corruptRecord:
            String(localized: "This record contains data the app doesn't recognise. Nothing was changed.", bundle: .l10n)
        case .sameWalletTransfer:
            String(localized: "Choose two different wallets for a transfer.", bundle: .l10n)
        case .missingDestinationWallet:
            String(localized: "Please choose the wallet that receives the money.", bundle: .l10n)
        case .missingReceivedAmount:
            String(localized: "These wallets use different currencies. Enter the amount that arrives in the destination wallet.", bundle: .l10n)
        case .transferAmountsDiffer:
            String(localized: "Both wallets use the same currency, so the amount sent and received must be equal.", bundle: .l10n)
        case .budgetNeedsCategories:
            String(localized: "Choose at least one expense category for this budget.", bundle: .l10n)
        case .budgetNeedsEndDate:
            String(localized: "A custom budget needs an end date.", bundle: .l10n)
        case .categoryUsedByBudget:
            String(localized: "This category is part of a budget. Remove it from the budget or archive the category instead.", bundle: .l10n)
        case .walletUsedByBudget:
            String(localized: "A budget is limited to this wallet. Change that budget first, or archive the wallet.", bundle: .l10n)
        case .invalidRecurrence:
            String(localized: "Repeat every 1 to 365 days, weeks, months or years, and end on or after the start date.", bundle: .l10n)
        case .duplicateOccurrence:
            String(localized: "This occurrence has already been recorded.", bundle: .l10n)
        case .withdrawalExceedsSavings:
            String(localized: "You can't take out more than has been saved for this goal.", bundle: .l10n)
        case .walletUsedByRecurring:
            String(localized: "A recurring transaction uses this wallet. Change or delete it first, or archive the wallet.", bundle: .l10n)
        case .categoryUsedByRecurring:
            String(localized: "A recurring transaction uses this category. Change or delete it first, or archive the category.", bundle: .l10n)
        case .walletUsedBySavingsGoal:
            String(localized: "A savings goal is linked to this wallet. Unlink it first, or archive the wallet.", bundle: .l10n)
        case .goalCurrencyLocked:
            String(localized: "The currency can't be changed because this goal already has contributions.", bundle: .l10n)
        case .invalidParentCategory:
            String(localized: "A sub-category goes under a top-level category of the same type.", bundle: .l10n)
        case .categoryHasSubcategories:
            String(localized: "This category has sub-categories, so it can't become a sub-category itself.", bundle: .l10n)
        case .categoryTypeInUse:
            String(localized: "This category is used by a budget, a recurring transaction or sub-categories, so it can't switch between income and expense.", bundle: .l10n)
        case .invalidAlertThresholds:
            String(localized: "Budget alerts can be set at 50, 80, 90 or 100 percent.", bundle: .l10n)
        }
    }
}
