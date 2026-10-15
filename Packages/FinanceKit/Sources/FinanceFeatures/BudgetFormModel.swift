import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// State and behaviour of the budget form, independent of SwiftUI.
///
/// Categories and wallets are tracked by id so toggling is cheap; `save`
/// resolves them against the lists the view provides.
@MainActor
@Observable
public final class BudgetFormModel {
    public enum Mode {
        case create
        case edit(Budget)
    }

    public let mode: Mode

    // MARK: Input

    public var name = ""
    public var amountText = ""

    /// Changing the currency clears the wallet selection, because a budget can
    /// only be limited to wallets in its own currency.
    public var currency: CurrencyDefinition {
        get { selectedCurrency }
        set {
            guard newValue != selectedCurrency else { return }
            selectedCurrency = newValue
            selectedWalletIDs = []
        }
    }

    public var period: BudgetPeriod = .monthly
    public var startDate: Date
    /// Recurring budgets only: stop after `endDate`. Custom budgets always end.
    public var hasEndDate = false
    public var endDate: Date
    public var selectedCategoryIDs: Set<UUID> = []
    /// When false the budget measures every wallet.
    public var limitsWallets = false
    public var selectedWalletIDs: Set<UUID> = []
    public var rolloverEnabled = false
    /// Alert percentages; empty means no alerts for this budget.
    public var alertThresholds: Set<Int> = Set(BudgetAlertRules.defaultThresholds)

    // MARK: Output

    public private(set) var failure: (any Error)?

    // MARK: Private

    private var selectedCurrency: CurrencyDefinition = CurrencyCatalog.defaultCurrency
    @ObservationIgnored private let service: BudgetService
    @ObservationIgnored private let parser: AmountInputParser

    public init(
        mode: Mode,
        service: BudgetService,
        now: Date = .now,
        calendar: CalendarPolicy = CalendarPolicy(),
        parser: AmountInputParser = AmountInputParser()
    ) {
        self.mode = mode
        self.service = service
        self.parser = parser

        let monthStart = calendar.calendar.dateInterval(of: .month, for: now)?.start ?? now
        self.startDate = monthStart
        self.endDate = calendar.calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? now

        if case .edit(let budget) = mode {
            name = budget.name
            selectedCurrency = budget.currency ?? CurrencyCatalog.defaultCurrency
            if let planned = budget.plannedAmount {
                amountText = parser.editingText(for: planned)
            }
            period = budget.period ?? .monthly
            startDate = budget.startDate
            if let end = budget.endDate {
                endDate = end
                hasEndDate = true
            }
            selectedCategoryIDs = Set(budget.categoryIDs)
            selectedWalletIDs = Set(budget.walletIDs)
            limitsWallets = !budget.walletIDs.isEmpty
            rolloverEnabled = budget.rolloverEnabled
            alertThresholds = Set(budget.alertThresholdPercents)
        }
    }

    // MARK: Derived state

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var requiresEndDate: Bool { period == .custom }

    /// The end date that will be saved: always for custom budgets, optional otherwise.
    public var effectiveEndDate: Date? {
        requiresEndDate || hasEndDate ? endDate : nil
    }

    /// Rollover only makes sense for repeating periods.
    public var supportsRollover: Bool { period != .custom }

    public var parsedAmount: Result<Money, any Error>? {
        guard !amountText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { try parser.parse(amountText, currency: currency) }
    }

    public var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .success(let amount)? = parsedAmount, amount.isPositive,
              !selectedCategoryIDs.isEmpty
        else { return false }
        if limitsWallets, selectedWalletIDs.isEmpty { return false }
        if let end = effectiveEndDate, end < startDate { return false }
        return true
    }

    /// Active expense categories, plus any already selected (even if archived),
    /// so editing never silently drops a category.
    public func selectableCategories(from all: [LedgerCategory]) -> [LedgerCategory] {
        all.filter { $0.type == .expense && (!$0.isArchived || selectedCategoryIDs.contains($0.id)) }
    }

    /// Active wallets in the budget's currency (`WalletChoices`).
    public func selectableWallets(from all: [Wallet]) -> [Wallet] {
        WalletChoices.selectable(from: all, currencyCode: currency.code)
    }

    /// Archived wallets this budget already counts. Not listed (and can't be
    /// added again), but kept, so the budget's past periods don't change.
    public func archivedSelectedWallets(from all: [Wallet]) -> [Wallet] {
        all.filter { $0.isArchived && selectedWalletIDs.contains($0.id) }
    }

    // MARK: Actions

    public func toggleAlert(_ threshold: Int) {
        if !alertThresholds.insert(threshold).inserted {
            alertThresholds.remove(threshold)
        }
    }

    public func toggleCategory(_ category: LedgerCategory) {
        if !selectedCategoryIDs.insert(category.id).inserted {
            selectedCategoryIDs.remove(category.id)
        }
    }

    public func toggleWallet(_ wallet: Wallet) {
        if !selectedWalletIDs.insert(wallet.id).inserted {
            selectedWalletIDs.remove(wallet.id)
        }
    }

    /// Creates or updates the budget.
    /// - Parameters:
    ///   - categories: every category the selection may refer to.
    ///   - wallets: every wallet the selection may refer to.
    /// - Returns: true on success; otherwise `failure` explains why and nothing was written.
    @discardableResult
    public func save(categories: [LedgerCategory], wallets: [Wallet]) -> Bool {
        do {
            let draft = BudgetDraft(
                name: name,
                plannedAmount: try parser.parse(amountText, currency: currency),
                period: period,
                startDate: startDate,
                endDate: effectiveEndDate,
                categories: categories.filter { selectedCategoryIDs.contains($0.id) },
                wallets: limitsWallets ? wallets.filter { selectedWalletIDs.contains($0.id) } : [],
                rolloverEnabled: supportsRollover && rolloverEnabled,
                alertThresholds: alertThresholds.sorted()
            )
            switch mode {
            case .create: try service.create(draft)
            case .edit(let budget): try service.update(budget, with: draft)
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
