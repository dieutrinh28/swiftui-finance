import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// State and behaviour of the sheet that records one due occurrence with a
/// different amount (a variable bill, a salary that changed this month).
///
/// Rules kept here (and tested) instead of in the view:
/// - the amount starts as the item's amount and is entered in its currency;
/// - a transfer between wallets in different currencies also needs the
///   amount received, prefilled from the item;
/// - if the item's wallets can't be read, that is shown and recording is off
///   (the received amount might be needed but can't be known).
@MainActor
@Observable
public final class RecordOccurrenceFormModel {
    public let item: DueOccurrence

    // MARK: Input

    public var amountText = ""
    /// Cross-currency transfers only.
    public var receivedText = ""

    // MARK: Output

    public private(set) var failure: (any Error)?
    /// The item's wallets couldn't be read when the sheet opened.
    public private(set) var loadFailure: (any Error)?
    /// The receiving wallet, set for a transfer between wallets in different currencies.
    public private(set) var crossCurrencyDestination: Wallet?

    @ObservationIgnored private let service: RecurringService
    @ObservationIgnored private let parser: AmountInputParser

    public init(item: DueOccurrence, service: RecurringService, parser: AmountInputParser = AmountInputParser()) {
        self.item = item
        self.service = service
        self.parser = parser

        let recurring = item.recurring
        if let amount = recurring.amount { amountText = parser.editingText(for: amount) }
        guard recurring.isTransfer else { return }
        do {
            if let source = try service.wallet(of: recurring),
               let destination = try service.destinationWallet(of: recurring),
               destination.currencyCode != source.currencyCode {
                crossCurrencyDestination = destination
                // convention-ok: C8 converts the item's own amount; no read from the store
                if let received = try? recurring.receivedAmount(in: destination) {
                    receivedText = parser.editingText(for: received)
                }
            }
        } catch {
            loadFailure = error
        }
    }

    // MARK: Derived state

    public var currency: CurrencyDefinition? { item.recurring.amount?.currency }

    public var needsReceivedAmount: Bool { crossCurrencyDestination != nil }

    public var parsedAmount: Result<Money, any Error>? {
        guard let currency, !amountText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { try parser.parse(amountText, currency: currency) }
    }

    public var parsedReceived: Result<Money, any Error>? {
        guard let currency = crossCurrencyDestination?.currency,
              !receivedText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { try parser.parse(receivedText, currency: currency) }
    }

    public var canSave: Bool {
        guard loadFailure == nil, case .success(let amount)? = parsedAmount, amount.isPositive else { return false }
        if needsReceivedAmount {
            guard case .success(let received)? = parsedReceived, received.isPositive else { return false }
        }
        return true
    }

    // MARK: Actions

    @discardableResult
    public func save() -> Bool {
        do {
            guard loadFailure == nil, let currency else { throw LedgerValidationError.corruptRecord }
            let received = try crossCurrencyDestination?.currency.map { try parser.parse(receivedText, currency: $0) }
            try service.record(item, amount: try parser.parse(amountText, currency: currency), received: received)
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
}
