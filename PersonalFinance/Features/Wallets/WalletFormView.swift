import SwiftUI
import FinanceDomain
import FinancePersistence

/// Create or edit a wallet. Edits are held in local state and only reach the
/// store through `WalletService` when the user taps Save.
struct WalletFormView: View {
    enum Mode {
        case create
        case edit(Wallet)
    }

    let mode: Mode
    /// Called with the saved wallet, e.g. to select it in the transaction form.
    var onSaved: ((Wallet) -> Void)? = nil

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: WalletType = .cash
    @State private var currency: CurrencyDefinition = CurrencyCatalog.defaultCurrency
    @State private var openingText = ""
    @State private var iconName = WalletType.cash.defaultIconName
    @State private var colorIdentifier = PaletteColor.green.rawValue
    @State private var note = ""
    @State private var iconWasChosen = false
    @State private var didLoad = false
    @State private var error: AlertError?

    private var editingWallet: Wallet? {
        if case .edit(let wallet) = mode { return wallet }
        return nil
    }

    private var currencyLocked: Bool { editingWallet?.hasHistory ?? false }

    private var isLiability: Bool { type.accountClass == .liability }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $type) {
                        ForEach(WalletType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.defaultIconName).tag(type)
                        }
                    }
                }

                if CurrencyCatalog.offersChoice(including: currency) {
                    Section {
                        Picker("Currency", selection: $currency) {
                            ForEach(CurrencyCatalog.pickerOptions(including: currency), id: \.self) { currency in
                                Text(currencyLabel(currency)).tag(currency)
                            }
                        }
                        .disabled(currencyLocked)
                    } footer: {
                        if currencyLocked {
                            Text("The currency can't change once the wallet has transactions.")
                        }
                    }
                }

                Section {
                    AmountField(text: $openingText, currency: currency)
                } header: {
                    Text(isLiability ? "Amount owed now" : "Opening balance")
                } footer: {
                    Text(isLiability
                         ? "What you currently owe on this card. It is recorded as debt, not as an expense."
                         : "Money already in this wallet. It is not counted as income. Leave empty for zero.")
                }

                Section("Appearance") {
                    HStack {
                        Spacer()
                        IconBadge(systemName: iconName, tint: PaletteColor(identifier: colorIdentifier).color)
                            .scaleEffect(1.4)
                            .padding(.vertical, Spacing.sm)
                        Spacer()
                    }
                    SymbolPicker(
                        selection: Binding(get: { iconName }, set: { iconName = $0; iconWasChosen = true }),
                        symbols: SymbolCatalog.wallets,
                        tint: PaletteColor(identifier: colorIdentifier).color
                    )
                    PalettePicker(selection: $colorIdentifier)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(editingWallet == nil ? "New Wallet" : "Edit Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onChange(of: type) { _, newType in
                if !iconWasChosen { iconName = newType.defaultIconName }
            }
            .onAppear(perform: loadIfNeeded)
            .errorAlert($error)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (try? parsedOpening()) != nil
    }

    private func parsedOpening() throws -> Money {
        if openingText.trimmingCharacters(in: .whitespaces).isEmpty { return .zero(currency) }
        return try AmountInputParser().parse(openingText, currency: currency)
    }

    private func currencyLabel(_ currency: CurrencyDefinition) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: currency.code) ?? currency.code
        return "\(currency.code) · \(name)"
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let wallet = editingWallet else { return }

        name = wallet.name
        type = wallet.type
        currency = wallet.currency ?? CurrencyCatalog.defaultCurrency
        if let opening = wallet.openingBalance,
           let entered = try? WalletRules.enteredOpeningBalance(stored: opening, accountClass: wallet.type.accountClass),
           !entered.isZero {
            openingText = AmountInputParser().editingText(for: entered)
        }
        iconName = wallet.iconName
        colorIdentifier = wallet.colorIdentifier
        note = wallet.note ?? ""
        iconWasChosen = true
    }

    private func save() {
        do {
            let draft = WalletDraft(
                name: name,
                type: type,
                currency: currency,
                enteredOpeningBalance: try parsedOpening(),
                iconName: iconName,
                colorIdentifier: colorIdentifier,
                note: note
            )
            let saved: Wallet
            if let wallet = editingWallet {
                try app.wallets.update(wallet, with: draft)
                saved = wallet
            } else {
                saved = try app.wallets.create(draft)
            }
            onSaved?(saved)
            dismiss()
        } catch {
            self.error = AlertError(error)
        }
    }
}

#Preview(traits: .emptyStore) {
    WalletFormView(mode: .create)
}
