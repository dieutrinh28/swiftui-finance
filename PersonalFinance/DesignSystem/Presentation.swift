import SwiftUI
import FinanceDomain
import FinancePersistence

// Display names and default icons for domain enums. Kept in the app target
// because they are presentation concerns, not financial rules.

extension WalletType {
    var displayName: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .bankAccount: String(localized: "Bank account")
        case .eWallet: String(localized: "E-wallet")
        case .savingsAccount: String(localized: "Savings account")
        case .creditCard: String(localized: "Credit card")
        case .investmentAccount: String(localized: "Investment account")
        case .other: String(localized: "Other")
        }
    }

    var defaultIconName: String {
        switch self {
        case .cash: "banknote"
        case .bankAccount: "building.columns"
        case .eWallet: "iphone"
        case .savingsAccount: "archivebox"
        case .creditCard: "creditcard"
        case .investmentAccount: "chart.line.uptrend.xyaxis"
        case .other: "wallet.pass"
        }
    }
}

extension CategoryType {
    var displayName: String {
        switch self {
        case .income: String(localized: "Income")
        case .expense: String(localized: "Expenses")
        }
    }
}

extension BudgetPeriod {
    var displayName: String {
        switch self {
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .yearly: String(localized: "Yearly")
        case .custom: String(localized: "Custom dates")
        }
    }
}

extension BudgetProgress.Status {
    var displayName: String {
        switch self {
        case .notStarted: String(localized: "Not started")
        case .onTrack: String(localized: "On track")
        case .nearLimit: String(localized: "Near limit")
        case .overBudget: String(localized: "Over budget")
        case .ended: String(localized: "Ended")
        }
    }

    var color: Color {
        switch self {
        case .notStarted, .ended: .secondary
        case .onTrack: AppColor.income
        case .nearLimit: AppColor.liability
        case .overBudget: AppColor.expense
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
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .yearly: String(localized: "Yearly")
        }
    }

    /// "Every 2 weeks", or the plain name when the interval is 1.
    func describe(interval: Int) -> String {
        guard interval > 1 else { return displayName }
        switch self {
        case .daily: return String(localized: "Every \(interval) days")
        case .weekly: return String(localized: "Every \(interval) weeks")
        case .monthly: return String(localized: "Every \(interval) months")
        case .yearly: return String(localized: "Every \(interval) years")
        }
    }
}

extension TransactionKind {
    var displayName: String {
        switch self {
        case .income: String(localized: "Income")
        case .expense: String(localized: "Expense")
        case .transfer: String(localized: "Transfer")
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
