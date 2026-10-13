import Foundation

/// Everything needed to decide whether a transfer between two wallets may be recorded.
public struct TransferCandidate: Sendable, Equatable {
    /// Amount leaving the source wallet, in its currency. Unsigned.
    public var sent: Money
    /// Amount arriving in the destination wallet, in its currency. Unsigned.
    public var received: Money
    public var sourceCurrency: CurrencyDefinition
    public var destinationCurrency: CurrencyDefinition
    public var isSameWallet: Bool
    public var sourceIsArchived: Bool
    public var destinationIsArchived: Bool

    public init(
        sent: Money,
        received: Money,
        sourceCurrency: CurrencyDefinition,
        destinationCurrency: CurrencyDefinition,
        isSameWallet: Bool = false,
        sourceIsArchived: Bool = false,
        destinationIsArchived: Bool = false
    ) {
        self.sent = sent
        self.received = received
        self.sourceCurrency = sourceCurrency
        self.destinationCurrency = destinationCurrency
        self.isSameWallet = isSameWallet
        self.sourceIsArchived = sourceIsArchived
        self.destinationIsArchived = destinationIsArchived
    }
}

/// Transfer invariants.
///
/// A transfer moves money between the user's own wallets. It is never income,
/// expense or budget spending. Between wallets of the same currency it preserves
/// the total exactly (sent == received). Between different currencies both
/// amounts are entered explicitly; the app never converts on its own.
extension LedgerRules {
    public static func validateTransfer(_ candidate: TransferCandidate) throws {
        guard !candidate.isSameWallet else {
            throw LedgerValidationError.sameWalletTransfer
        }
        guard candidate.sent.isPositive, candidate.received.isPositive else {
            throw LedgerValidationError.nonPositiveAmount
        }
        guard candidate.sent.currency == candidate.sourceCurrency else {
            throw LedgerValidationError.currencyMismatch(
                walletCurrency: candidate.sourceCurrency.code,
                amountCurrency: candidate.sent.currency.code
            )
        }
        guard candidate.received.currency == candidate.destinationCurrency else {
            throw LedgerValidationError.currencyMismatch(
                walletCurrency: candidate.destinationCurrency.code,
                amountCurrency: candidate.received.currency.code
            )
        }
        guard !candidate.sourceIsArchived, !candidate.destinationIsArchived else {
            throw LedgerValidationError.archivedWallet
        }
        if candidate.sourceCurrency == candidate.destinationCurrency,
           candidate.sent.minorUnits != candidate.received.minorUnits {
            throw LedgerValidationError.transferAmountsDiffer
        }
    }

    /// The rate implied by a cross-currency transfer: destination major units
    /// per source major unit (e.g. 25,400 VND per USD). nil for same-currency transfers.
    public static func impliedExchangeRate(sent: Money, received: Money) -> Decimal? {
        guard sent.currency != received.currency, sent.isPositive, received.isPositive else { return nil }
        return received.majorUnits / sent.majorUnits
    }
}
