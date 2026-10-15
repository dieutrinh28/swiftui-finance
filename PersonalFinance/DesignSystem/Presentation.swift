import SwiftUI
import FinanceDomain
import FinancePersistence

// Display names (and some icons) for domain enums. Kept in the app target
// because they are presentation concerns, not financial rules.

extension WalletType {
    var displayName: String {
        switch self {
        case .cash: String(localized: "Cash", bundle: .l10n)
        case .bankAccount: String(localized: "Bank account", bundle: .l10n)
        case .eWallet: String(localized: "E-wallet", bundle: .l10n)
        case .savingsAccount: String(localized: "Savings account", bundle: .l10n)
        case .creditCard: String(localized: "Credit card", bundle: .l10n)
        case .investmentAccount: String(localized: "Investment account", bundle: .l10n)
        case .other: String(localized: "Other", bundle: .l10n)
        }
    }
}

extension CategoryType {
    var displayName: String {
        switch self {
        case .income: String(localized: "Income", bundle: .l10n)
        case .expense: String(localized: "Expenses", bundle: .l10n)
        }
    }
}

extension BudgetPeriod {
    var displayName: String {
        switch self {
        case .weekly: String(localized: "Weekly", bundle: .l10n)
        case .monthly: String(localized: "Monthly", bundle: .l10n)
        case .yearly: String(localized: "Yearly", bundle: .l10n)
        case .custom: String(localized: "Custom dates", bundle: .l10n)
        }
    }
}

extension BudgetProgress.Status {
    var displayName: String {
        switch self {
        case .notStarted: String(localized: "Not started", bundle: .l10n)
        case .onTrack: String(localized: "On track", bundle: .l10n)
        case .nearLimit: String(localized: "Near limit", bundle: .l10n)
        case .overBudget: String(localized: "Over budget", bundle: .l10n)
        case .ended: String(localized: "Ended", bundle: .l10n)
        }
    }

    var color: Color {
        switch self {
        case .notStarted, .ended: AppColor.textSecondary
        case .onTrack: AppColor.positive
        case .nearLimit: AppColor.warning
        case .overBudget: AppColor.negative
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: "clock"
        case .onTrack: "checkmark.circle"
        case .nearLimit: "exclamationmark.circle"
        case .overBudget: "exclamationmark.triangle"
        case .ended: "flag.checkered"
        }
    }
}

extension RecurrenceFrequency {
    var displayName: String {
        switch self {
        case .daily: String(localized: "Daily", bundle: .l10n)
        case .weekly: String(localized: "Weekly", bundle: .l10n)
        case .monthly: String(localized: "Monthly", bundle: .l10n)
        case .yearly: String(localized: "Yearly", bundle: .l10n)
        }
    }

    /// "Every 2 weeks", or the plain name when the interval is 1.
    func describe(interval: Int) -> String {
        guard interval > 1 else { return displayName }
        switch self {
        case .daily: return String(localized: "Every \(interval) days", bundle: .l10n)
        case .weekly: return String(localized: "Every \(interval) weeks", bundle: .l10n)
        case .monthly: return String(localized: "Every \(interval) months", bundle: .l10n)
        case .yearly: return String(localized: "Every \(interval) years", bundle: .l10n)
        }
    }
}

extension TransactionKind {
    var displayName: String {
        switch self {
        case .income: String(localized: "Income", bundle: .l10n)
        case .expense: String(localized: "Expense", bundle: .l10n)
        case .transfer: String(localized: "Transfer", bundle: .l10n)
        }
    }

    var tone: AmountTone {
        switch self {
        case .income: .income
        case .expense: .expense
        case .transfer: .transfer
        }
    }
}

// MARK: - Currency display

extension Wallet {
    /// "Cash", or "Cash · USD" when the currency code carries information
    /// (multi-currency enabled, or a wallet outside the default currency).
    var nameWithCurrency: String {
        CurrencyCatalog.showsCode(currencyCode) ? "\(name) · \(currencyCode)" : name
    }

    /// "Bank account", or "Bank account · USD" (same rule as `nameWithCurrency`).
    var typeWithCurrency: String {
        CurrencyCatalog.showsCode(currencyCode) ? "\(type.displayName) · \(currencyCode)" : type.displayName
    }
}
