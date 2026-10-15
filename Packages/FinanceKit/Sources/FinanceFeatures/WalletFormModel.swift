import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// State and behaviour of the wallet form.
///
/// Rules kept here (and tested) instead of in the view:
/// - the currency is locked once the wallet has transactions (the service also
///   refuses a change while recurring items, budgets or goals use the wallet);
/// - the icon follows the wallet type until the user picks one;
/// - an empty opening balance means zero; a liability's opening balance is the
///   amount owed, entered as a positive number.
@MainActor
@Observable
public final class WalletFormModel {
    public enum Mode {
        case create
        case edit(Wallet)
    }

    public let mode: Mode

    // MARK: Input

    public var name = ""

    /// Changing the type also changes the icon while the user hasn't picked one.
    public var type: WalletType {
        get { selectedType }
        set {
            selectedType = newValue
            if !iconWasChosen { selectedIcon = newValue.defaultIconName }
        }
    }

    /// Ignored while `currencyLocked`.
    public var currency: CurrencyDefinition {
        get { selectedCurrency }
        set {
            guard !currencyLocked else { return }
            selectedCurrency = newValue
        }
    }

    /// The opening balance as typed; empty means zero.
    public var openingText = ""

    /// Setting it marks the icon as chosen, so a later type change keeps it.
    public var iconName: String {
        get { selectedIcon }
        set {
            selectedIcon = newValue
            iconWasChosen = true
        }
    }

    public var colorIdentifier = "green"
    public var note = ""

    // MARK: Output

    public private(set) var failure: (any Error)?

    // MARK: Private

    private var selectedType: WalletType = .cash
    private var selectedCurrency: CurrencyDefinition = CurrencyCatalog.defaultCurrency
    private var selectedIcon = WalletType.cash.defaultIconName
    private var iconWasChosen = false
    @ObservationIgnored private let service: WalletService
    @ObservationIgnored private let parser: AmountInputParser

    public init(mode: Mode, service: WalletService, parser: AmountInputParser = AmountInputParser()) {
        self.mode = mode
        self.service = service
        self.parser = parser

        if case .edit(let wallet) = mode {
            name = wallet.name
            selectedType = wallet.type
            selectedCurrency = wallet.currency ?? CurrencyCatalog.defaultCurrency
            if let opening = wallet.openingBalance,
               let entered = try? WalletRules.enteredOpeningBalance(stored: opening, accountClass: wallet.type.accountClass),
               !entered.isZero {
                openingText = parser.editingText(for: entered)
            }
            selectedIcon = wallet.iconName
            iconWasChosen = true
            colorIdentifier = wallet.colorIdentifier
            note = wallet.note ?? ""
        }
    }

    // MARK: Derived state

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingWallet: Wallet? {
        if case .edit(let wallet) = mode { return wallet }
        return nil
    }

    /// Transactions are recorded in this currency, so it can't change.
    public var currencyLocked: Bool { editingWallet?.hasHistory ?? false }

    /// A credit card or loan: the opening balance is what is owed.
    public var isLiability: Bool { selectedType.accountClass == .liability }

    public var currencyOptions: [CurrencyDefinition] {
        CurrencyCatalog.pickerOptions(including: selectedCurrency)
    }

    /// Hidden when only one currency is enabled.
    public var showsCurrencyPicker: Bool { CurrencyCatalog.offersChoice(including: selectedCurrency) }

    /// Zero when nothing is entered.
    public var parsedOpening: Result<Money, any Error> {
        if openingText.trimmingCharacters(in: .whitespaces).isEmpty { return .success(.zero(selectedCurrency)) }
        return Result { try parser.parse(openingText, currency: selectedCurrency) }
    }

    public var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .success = parsedOpening
        else { return false }
        return true
    }

    // MARK: Actions

    /// The saved wallet, or nil with `failure` set.
    @discardableResult
    public func save() -> Wallet? {
        do {
            let draft = WalletDraft(
                name: name,
                type: selectedType,
                currency: selectedCurrency,
                enteredOpeningBalance: try parsedOpening.get(),
                iconName: selectedIcon,
                colorIdentifier: colorIdentifier,
                note: note
            )
            let saved: Wallet
            switch mode {
            case .create:
                saved = try service.create(draft)
            case .edit(let wallet):
                try service.update(wallet, with: draft)
                saved = wallet
            }
            failure = nil
            return saved
        } catch {
            failure = error
            return nil
        }
    }

    public func clearFailure() {
        failure = nil
    }
}
