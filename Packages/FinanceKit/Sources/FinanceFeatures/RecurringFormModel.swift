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

    /// Switching kind clears a category of the wrong type (transfers have none).
    public var kind: TransactionKind {
        get { selectedKind }
        set {
            selectedKind = newValue
            if let category, category.type != newValue.requiredCategoryType { self.category = nil }
        }
    }

    /// The amount of an income/expense, or the amount sent by a transfer.
    public var amountText = ""
    /// The wallet of an income/expense, or the source of a transfer.
    public var wallet: Wallet? {
        didSet { if destination?.id == wallet?.id { destination = nil } }
    }
    public var category: LedgerCategory?
    /// Transfers only.
    public var destination: Wallet?
    /// Transfers between currencies only: the amount arriving in `destination`.
    public var receivedText = ""
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
    /// Wallets this item used that are archived now. They are not offered, so
    /// the form asks for another wallet (the item is on hold until then).
    public private(set) var archivedWalletNames: [String] = []
    /// The item's wallet or category couldn't be read when the form opened.
    /// Shown, and saving is off: empty fields would otherwise look like the item's data.
    public private(set) var loadFailure: (any Error)?

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
            do {
                let source = try service.wallet(of: recurring)
                let target = try service.destinationWallet(of: recurring)
                archivedWalletNames = [source, target].compactMap { $0 }.filter(\.isArchived).map(\.name)
                wallet = source?.isArchived == false ? source : nil
                category = try service.category(of: recurring)
                destination = target?.isArchived == false ? target : nil
            } catch {
                loadFailure = error
            }
            // convention-ok: C8 converts the item's own amount; no read from the store
            if let destination, let received = try? recurring.receivedAmount(in: destination) {
                receivedText = parser.editingText(for: received)
            }
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

    public var isTransfer: Bool { kind == .transfer }

    /// A transfer between wallets in different currencies needs the received amount.
    public var needsReceivedAmount: Bool {
        guard isTransfer, let source = wallet, let destination else { return false }
        return source.currencyCode != destination.currencyCode
    }

    public var parsedReceived: Result<Money, any Error>? {
        guard needsReceivedAmount, let currency = destination?.currency,
              !receivedText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { try parser.parse(receivedText, currency: currency) }
    }

    /// Wallets the item can use: active ones (`WalletChoices`).
    public func walletChoices(from wallets: [Wallet]) -> [Wallet] {
        WalletChoices.selectable(from: wallets)
    }

    /// Wallets a transfer can go to: any other active wallet.
    public func destinationChoices(from wallets: [Wallet]) -> [Wallet] {
        WalletChoices.selectable(from: wallets, excluding: wallet)
    }

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
        guard loadFailure == nil,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              wallet != nil,
              case .success(let amount)? = parsedAmount, amount.isPositive,
              RecurrenceRules.intervalRange.contains(interval)
        else { return false }
        if isTransfer {
            guard let destination, destination.id != wallet?.id else { return false }
            if needsReceivedAmount {
                guard case .success(let received)? = parsedReceived, received.isPositive else { return false }
            }
        } else if category == nil {
            return false
        }
        if hasEndDate, endDate < startDate { return false }
        return true
    }

    // MARK: Actions

    /// New items start with the first active wallet. An edited item whose
    /// wallet was archived keeps the choice empty, so the user picks one.
    public func selectDefaultWalletIfNeeded(from wallets: [Wallet]) {
        guard wallet == nil, !isEditing else { return }
        wallet = WalletChoices.selectable(from: wallets).first
    }

    @discardableResult
    public func save() -> Bool {
        do {
            guard let wallet else { throw TransactionFormError.missingWallet }
            guard let currency = wallet.currency else { throw LedgerValidationError.corruptRecord }
            if !isTransfer, category == nil { throw LedgerValidationError.missingCategory }
            var received: Money?
            if needsReceivedAmount, let destinationCurrency = destination?.currency {
                received = try parser.parse(receivedText, currency: destinationCurrency)
            }
            let draft = RecurringDraft(
                name: name,
                kind: kind,
                amount: try parser.parse(amountText, currency: currency),
                wallet: wallet,
                category: isTransfer ? nil : category,
                destination: isTransfer ? destination : nil,
                receivedAmount: received,
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
