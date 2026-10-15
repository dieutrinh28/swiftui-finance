import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// State and behaviour of the sheet that adds money to a savings goal or takes some out.
///
/// Rules kept here (and tested) instead of in the view:
/// - the amount is entered in the goal's currency and must be positive;
/// - a withdrawal can't take out more than is set aside (checked by
///   `SavingsService`; the error is kept for the view to show).
@MainActor
@Observable
public final class ContributionFormModel {
    public let goal: SavingsGoal
    public let isWithdrawal: Bool

    // MARK: Input

    public var amountText = ""
    public var date: Date
    public var note = ""

    // MARK: Output

    public private(set) var failure: (any Error)?

    @ObservationIgnored private let service: SavingsService
    @ObservationIgnored private let parser: AmountInputParser

    public init(
        goal: SavingsGoal,
        isWithdrawal: Bool,
        service: SavingsService,
        now: Date = .now,
        parser: AmountInputParser = AmountInputParser()
    ) {
        self.goal = goal
        self.isWithdrawal = isWithdrawal
        self.service = service
        self.parser = parser
        self.date = now
    }

    // MARK: Derived state

    /// nil when the goal's stored currency is unknown (the sheet can't take an amount).
    public var currency: CurrencyDefinition? { goal.currency }

    public var parsedAmount: Result<Money, any Error>? {
        guard let currency, !amountText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { try parser.parse(amountText, currency: currency) }
    }

    public var canSave: Bool {
        guard case .success(let amount)? = parsedAmount else { return false }
        return amount.isPositive
    }

    // MARK: Actions

    @discardableResult
    public func save() -> Bool {
        do {
            guard let currency else { throw LedgerValidationError.corruptRecord }
            try service.addEntry(
                to: goal,
                amount: try parser.parse(amountText, currency: currency),
                isWithdrawal: isWithdrawal,
                date: date,
                note: note
            )
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
