import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// State and behaviour of the savings-goal form.
///
/// Rules kept here (and tested) instead of in the view:
/// - the currency is locked once the goal has contributions;
/// - changing the currency drops a linked wallet in another currency;
/// - only wallets in the goal's currency can be linked;
/// - a live "save about X per month" estimate from target, date and what is already saved.
@MainActor
@Observable
public final class SavingsGoalFormModel {
    public enum Mode {
        case create
        case edit(SavingsGoal)
    }

    public let mode: Mode

    // MARK: Input

    public var name = ""

    /// Ignored while `currencyLocked`. Clears a linked wallet in another currency.
    public var currency: CurrencyDefinition {
        get { selectedCurrency }
        set {
            guard !currencyLocked, newValue != selectedCurrency else { return }
            selectedCurrency = newValue
            if let linkedWallet, linkedWallet.currencyCode != newValue.code { self.linkedWallet = nil }
        }
    }

    public var targetText = ""
    public var hasTargetDate = true
    public var targetDate: Date

    /// Ignores a wallet in another currency.
    public var linkedWallet: Wallet? {
        get { selectedWallet }
        set {
            if let newValue, newValue.currencyCode != selectedCurrency.code { return }
            selectedWallet = newValue
        }
    }

    public var note = ""
    public var iconName = "target"
    public var colorIdentifier = "teal"

    // MARK: Output

    public private(set) var failure: (any Error)?

    // MARK: Private

    private var selectedCurrency: CurrencyDefinition = CurrencyCatalog.defaultCurrency
    private var selectedWallet: Wallet?
    @ObservationIgnored private let service: SavingsService
    @ObservationIgnored private let policy: CalendarPolicy
    @ObservationIgnored private let parser: AmountInputParser
    @ObservationIgnored private let now: () -> Date

    public init(
        mode: Mode,
        service: SavingsService,
        policy: CalendarPolicy = CalendarPolicy(),
        now: @escaping () -> Date = { .now },
        parser: AmountInputParser = AmountInputParser()
    ) {
        self.mode = mode
        self.service = service
        self.policy = policy
        self.now = now
        self.parser = parser
        let today = policy.calendar.startOfDay(for: now())
        self.targetDate = policy.calendar.date(byAdding: .month, value: 12, to: today) ?? today

        if case .edit(let goal) = mode {
            name = goal.name
            selectedCurrency = goal.currency ?? CurrencyCatalog.defaultCurrency
            if let target = goal.target { targetText = parser.editingText(for: target) }
            hasTargetDate = goal.targetDate != nil
            if let date = goal.targetDate { targetDate = date }
            selectedWallet = try? service.linkedWallet(of: goal)
            note = goal.note ?? ""
            iconName = goal.iconName
            colorIdentifier = goal.colorIdentifier
        }
    }

    // MARK: Derived state

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingGoal: SavingsGoal? {
        if case .edit(let goal) = mode { return goal }
        return nil
    }

    /// Money has been put aside in this currency, so it can't change.
    public var currencyLocked: Bool {
        !(editingGoal?.contributionsNewestFirst.isEmpty ?? true)
    }

    public var currencyOptions: [CurrencyDefinition] {
        CurrencyCatalog.pickerOptions(including: selectedCurrency)
    }

    /// Hidden when only one currency is enabled.
    public var showsCurrencyPicker: Bool { currencyOptions.count > 1 }

    /// Earliest selectable target date (today).
    public var earliestTargetDate: Date { policy.calendar.startOfDay(for: now()) }

    public var parsedTarget: Result<Money, any Error>? {
        guard !targetText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { try parser.parse(targetText, currency: selectedCurrency) }
    }

    public var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .success(let target)? = parsedTarget, target.isPositive
        else { return false }
        return true
    }

    /// Progress with the values currently in the form, including money
    /// already saved when editing. nil until a valid target is entered.
    public var estimate: SavingsProgress? {
        guard case .success(let target)? = parsedTarget, target.isPositive else { return nil }
        let entries = (editingGoal?.contributionsNewestFirst ?? []).map {
            Money(minorUnits: $0.amountMinorUnits, currency: target.currency)
        }
        return try? SavingsRules.progress(
            target: target, entries: entries,
            targetDate: hasTargetDate ? targetDate : nil,
            reference: now(), policy: policy
        )
    }

    /// Wallets that can be linked: same currency, active (or already linked).
    public func availableWallets(from all: [Wallet]) -> [Wallet] {
        all.filter {
            $0.currencyCode == selectedCurrency.code && (!$0.isArchived || $0.id == selectedWallet?.id)
        }
    }

    // MARK: Actions

    @discardableResult
    public func save() -> Bool {
        do {
            let draft = SavingsGoalDraft(
                name: name,
                target: try parser.parse(targetText, currency: selectedCurrency),
                targetDate: hasTargetDate ? targetDate : nil,
                linkedWallet: selectedWallet,
                note: note,
                iconName: iconName,
                colorIdentifier: colorIdentifier
            )
            switch mode {
            case .create: try service.create(draft)
            case .edit(let goal): try service.update(goal, with: draft)
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
}
