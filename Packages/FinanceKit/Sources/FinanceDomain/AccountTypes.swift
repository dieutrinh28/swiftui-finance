import Foundation

// Raw values are persisted. Never rename an existing case's raw value;
// add a migration instead.

/// What kind of account a wallet represents.
public enum WalletType: String, CaseIterable, Codable, Sendable {
    case cash
    case bankAccount
    case eWallet
    case savingsAccount
    case creditCard
    case investmentAccount
    case other

    public var accountClass: AccountClass {
        self == .creditCard ? .liability : .asset
    }
}

/// Assets count towards total assets. Liabilities count towards total liabilities.
///
/// Balance sign convention (same for both classes): a positive balance is money
/// the user has, a negative balance is money the user owes. A credit card
/// with 2,000,000 VND of debt therefore has a balance of -2,000,000 VND.
public enum AccountClass: String, Codable, Sendable {
    case asset
    case liability
}

public enum CategoryType: String, CaseIterable, Codable, Sendable {
    case income
    case expense
}

public enum TransactionKind: String, CaseIterable, Codable, Sendable {
    case income
    case expense
    case transfer

    /// Transfers move money between the user's own wallets. They never count
    /// as income, expense or budget spending.
    public var countsAsCashFlow: Bool { self != .transfer }

    /// The category type a transaction of this kind must use, if any.
    public var requiredCategoryType: CategoryType? {
        switch self {
        case .income: .income
        case .expense: .expense
        case .transfer: nil
        }
    }
}
