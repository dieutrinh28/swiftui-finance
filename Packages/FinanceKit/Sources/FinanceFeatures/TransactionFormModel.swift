import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// Problems the form itself detects before calling the service.
public enum TransactionFormError: Error, Equatable, Sendable {
    case missingWallet
}

extension TransactionFormError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingWallet: String(localized: "Please choose a wallet.", bundle: .l10n)
        }
    }
}

/// State and behaviour of the transaction form (income, expense, transfer),
/// independent of SwiftUI.
///
/// - Input: plain properties the view binds to. Nothing is written to the
///   store while the user edits.
/// - Derived state: `parsedAmount`, `needsReceivedAmount`, `canSave`, …
/// - Action: `save()` builds a draft and hands it to `TransactionService`,
///   which validates and saves atomically. A failure is kept in `failure`
///   for the view to present; the store is left unchanged.
@MainActor
@Observable
public final class TransactionFormModel {
    public enum Mode {
        case create(wallet: Wallet?)
        case edit(LedgerTransaction)
    }

    public let mode: Mode

    // MARK: Input

    /// Switching kind clears anything that no longer fits: a category of the
    /// wrong type, or any category when switching to a transfer.
    public var kind: TransactionKind {
        get { selectedKind }
        set {
            selectedKind = newValue
            if let category, category.type != newValue.requiredCategoryType {
                self.category = nil
            }
        }
    }

    /// Income/expense wallet, or the source wallet of a transfer.
    public var wallet: Wallet?
    /// Transfers only: the wallet receiving the money.
    public var destinationWallet: Wallet?
    /// Amount in `wallet`'s currency (the amount sent, for a transfer).
    public var amountText = ""
    /// Transfers between different currencies only: amount arriving in `destinationWallet`.
    public var receivedAmountText = ""
    /// Choosing a category also sets `isIrregular` to the category's default,
    /// until the user changes the toggle themselves.
    public var category: LedgerCategory? {
        didSet {
            guard !irregularChosenByUser, category?.id != oldValue?.id else { return }
            selectedIrregular = category?.isIrregular ?? false
        }
    }
    /// Expenses only: counts in balances but not in spending or budgets.
    public var isIrregular: Bool {
        get { selectedIrregular }
        set {
            selectedIrregular = newValue
            irregularChosenByUser = true
        }
    }
    public var date: Date
    public var note = ""
    public var merchant = ""

    // MARK: Output

    /// The error from the last failed `save()`, until cleared.
    public private(set) var failure: (any Error)?

    // MARK: Private

    private var selectedKind: TransactionKind = .expense
    private var selectedIrregular = false
    @ObservationIgnored private var irregularChosenByUser = false
    @ObservationIgnored private let service: TransactionService
    @ObservationIgnored private let parser: AmountInputParser

    public init(
        mode: Mode,
        service: TransactionService,
        now: Date = .now,
        parser: AmountInputParser = AmountInputParser()
    ) {
        self.mode = mode
        self.service = service
        self.parser = parser
        self.date = now

        switch mode {
        case .create(let preselected):
            wallet = preselected
        case .edit(let transaction):
            selectedKind = transaction.kind ?? .expense
            date = transaction.date
            note = transaction.note ?? ""
            merchant = transaction.merchant ?? ""
            if transaction.kind == .transfer {
                wallet = transaction.transferSource?.wallet
                destinationWallet = transaction.transferDestination?.wallet
                if let sent = transaction.transferSource?.magnitude {
                    amountText = parser.editingText(for: sent)
                }
                if let received = transaction.transferDestination?.magnitude, received.currency != currency {
                    receivedAmountText = parser.editingText(for: received)
                }
            } else {
                wallet = transaction.primaryWallet
                category = transaction.category
                selectedIrregular = transaction.isIrregular
                irregularChosenByUser = true          // keep what was saved
                if let amount = transaction.displayAmount {
                    amountText = parser.editingText(for: amount)
                }
            }
        }
    }

    // MARK: Derived state

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var isTransfer: Bool { kind == .transfer }

    /// The irregular toggle is offered for expenses only.
    public var offersIrregular: Bool { kind == .expense }

    /// A new transaction can be any kind. An existing transfer stays a transfer,
    /// and an existing income/expense can only switch between the two.
    public var availableKinds: [TransactionKind] {
        guard case .edit(let transaction) = mode else { return [.expense, .income, .transfer] }
        return transaction.kind == .transfer ? [.transfer] : [.expense, .income]
    }

    /// Currency of `wallet`; the (sent) amount is always entered in it.
    public var currency: CurrencyDefinition? { wallet?.currency }

    public var destinationCurrency: CurrencyDefinition? { destinationWallet?.currency }

    public var requiredCategoryType: CategoryType {
        kind.requiredCategoryType ?? .expense
    }

    /// True when a transfer crosses currencies, so the received amount must be entered.
    public var needsReceivedAmount: Bool {
        guard isTransfer, let currency, let destinationCurrency else { return false }
        return currency != destinationCurrency
    }

    /// nil while the amount field is empty or no wallet is chosen.
    public var parsedAmount: Result<Money, any Error>? {
        parse(amountText, in: currency)
    }

    /// nil unless a received amount is needed and something was typed.
    public var parsedReceivedAmount: Result<Money, any Error>? {
        needsReceivedAmount ? parse(receivedAmountText, in: destinationCurrency) : nil
    }

    /// Destination units per source unit, shown for cross-currency transfers.
    public var impliedExchangeRate: Decimal? {
        guard case .success(let sent)? = parsedAmount, case .success(let received)? = parsedReceivedAmount else {
            return nil
        }
        return LedgerRules.impliedExchangeRate(sent: sent, received: received)
    }

    /// Enables the Save button. The service still re-validates on save.
    public var canSave: Bool {
        guard wallet != nil, case .success(let amount)? = parsedAmount, amount.isPositive else { return false }
        if isTransfer {
            guard let destinationWallet, destinationWallet.id != wallet?.id else { return false }
            if needsReceivedAmount {
                guard case .success(let received)? = parsedReceivedAmount, received.isPositive else { return false }
            }
            return true
        }
        return category != nil
    }

    // MARK: Actions

    /// Picks the first active wallet when none is selected yet.
    public func selectDefaultWalletIfNeeded(from wallets: [Wallet]) {
        guard wallet == nil else { return }
        wallet = WalletChoices.selectable(from: wallets).first
    }

    /// Records or updates the transaction.
    /// - Returns: true on success. On failure `failure` explains why and nothing was written.
    @discardableResult
    public func save() -> Bool {
        do {
            guard let wallet else { throw TransactionFormError.missingWallet }
            guard let currency = wallet.currency else { throw LedgerValidationError.corruptRecord }
            let amount = try parser.parse(amountText, currency: currency)

            if isTransfer {
                try saveTransfer(from: wallet, sent: amount)
            } else {
                try saveCashFlow(in: wallet, amount: amount)
            }
            failure = nil
            return true
        } catch {
            failure = error
            return false
        }
    }

    public func clearFailure() {
        failure = nil
    }

    // MARK: Private

    private func saveCashFlow(in wallet: Wallet, amount: Money) throws {
        let draft = CashFlowDraft(
            kind: kind, amount: amount, wallet: wallet, category: category,
            date: date, note: note, merchant: merchant,
            isIrregular: kind == .expense ? isIrregular : false
        )
        switch mode {
        case .create: try service.create(draft)
        case .edit(let transaction): try service.update(transaction, with: draft)
        }
    }

    private func saveTransfer(from wallet: Wallet, sent: Money) throws {
        var received: Money?
        if needsReceivedAmount, let destinationCurrency {
            received = try parser.parse(receivedAmountText, currency: destinationCurrency)
        }
        let draft = TransferDraft(
            source: wallet, destination: destinationWallet, sent: sent,
            received: received, date: date, note: note
        )
        switch mode {
        case .create: try service.createTransfer(draft)
        case .edit(let transaction): try service.updateTransfer(transaction, with: draft)
        }
    }

    private func parse(_ text: String, in currency: CurrencyDefinition?) -> Result<Money, any Error>? {
        guard let currency, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { try parser.parse(text, currency: currency) }
    }
}
