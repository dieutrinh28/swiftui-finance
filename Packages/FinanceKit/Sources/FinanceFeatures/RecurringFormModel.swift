import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// State and behaviour of the recurring-transaction form.
@MainActor
@Observable
public final class RecurringFormModel {
    public enum Mode {
        case create
        case edit(RecurringTransaction)
    }

    public let mode: Mode

    // MARK: Input

    public var name = ""

    /// Switching kind clears a category of the wrong type.
    public var kind: TransactionKind {
        get { selectedKind }
        set {
            selectedKind = newValue
            if let category, category.type != newValue.requiredCategoryType { self.category = nil }
        }
    }

    public var amountText = ""
    public var wallet: Wallet?
    public var category: LedgerCategory?
    public var frequency: RecurrenceFrequency = .monthly
    public var interval = 1
    public var startDate: Date
    public var hasEndDate = false
    public var endDate: Date
    public var note = ""
    public var reminderEnabled = false
    /// Minutes after midnight (540 = 09:00).
    public var reminderMinutes = 9 * 60

    // MARK: Output

    public private(set) var failure: (any Error)?

    // MARK: Private

    private var selectedKind: TransactionKind = .expense
    @ObservationIgnored private let service: RecurringService
    @ObservationIgnored private let policy: CalendarPolicy
    @ObservationIgnored private let parser: AmountInputParser
    @ObservationIgnored private let now: () -> Date

    public init(
        mode: Mode,
        service: RecurringService,
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
        self.startDate = today
        self.endDate = policy.calendar.date(byAdding: .year, value: 1, to: today) ?? today

        if case .edit(let recurring) = mode {
            name = recurring.name
            selectedKind = recurring.kind ?? .expense
            if let amount = recurring.amount { amountText = parser.editingText(for: amount) }
            wallet = try? service.wallet(of: recurring)
            category = try? service.category(of: recurring)
            frequency = recurring.frequency ?? .monthly
            interval = recurring.interval
            startDate = recurring.startDate
            if let end = recurring.endDate {
                hasEndDate = true
                endDate = end
            }
            note = recurring.note ?? ""
            reminderEnabled = recurring.reminderEnabled
            reminderMinutes = recurring.reminderMinutes
        }
    }

    // MARK: Derived state

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var currency: CurrencyDefinition? { wallet?.currency }

    public var requiredCategoryType: CategoryType { kind.requiredCategoryType ?? .expense }

    public var parsedAmount: Result<Money, any Error>? {
        guard let currency, !amountText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { try parser.parse(amountText, currency: currency) }
    }

    public var schedule: RecurrenceSchedule {
        RecurrenceSchedule(frequency: frequency, interval: interval, startDate: startDate, endDate: hasEndDate ? endDate : nil)
    }

    /// The next due day from today, for a live preview in the form.
    public var nextOccurrence: Date? {
        RecurrenceRules.next(of: schedule, onOrAfter: now(), policy: policy)?.date
    }

    /// The reminder time as a date today (for a time picker).
    public var reminderTime: Date {
        get {
            policy.calendar.date(byAdding: .minute, value: reminderMinutes, to: policy.calendar.startOfDay(for: now())) ?? now()
        }
        set {
            let parts = policy.calendar.dateComponents([.hour, .minute], from: newValue)
            reminderMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        }
    }

    public var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              wallet != nil, category != nil,
              case .success(let amount)? = parsedAmount, amount.isPositive,
              RecurrenceRules.intervalRange.contains(interval)
        else { return false }
        if hasEndDate, endDate < startDate { return false }
        return true
    }

    // MARK: Actions

    public func selectDefaultWalletIfNeeded(from wallets: [Wallet]) {
        guard wallet == nil else { return }
        wallet = wallets.first { !$0.isArchived }
    }

    @discardableResult
    public func save() -> Bool {
        do {
            guard let wallet else { throw TransactionFormError.missingWallet }
            guard let category else { throw LedgerValidationError.missingCategory }
            guard let currency = wallet.currency else { throw LedgerValidationError.corruptRecord }
            let draft = RecurringDraft(
                name: name,
                kind: kind,
                amount: try parser.parse(amountText, currency: currency),
                wallet: wallet,
                category: category,
                schedule: schedule,
                note: note,
                reminderEnabled: reminderEnabled,
                reminderMinutes: reminderMinutes
            )
            switch mode {
            case .create: try service.create(draft)
            case .edit(let recurring): try service.update(recurring, with: draft)
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
