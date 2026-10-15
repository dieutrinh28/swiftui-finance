import SwiftUI
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Create or edit a wallet. Logic lives in `WalletFormModel`; nothing reaches
/// the store until the user taps Save.
struct WalletFormView: View {
    let mode: WalletFormModel.Mode
    /// Called with the saved wallet, e.g. to select it in the transaction form.
    var onSaved: ((Wallet) -> Void)? = nil

    @Environment(AppContainer.self) private var app
    @State private var model: WalletFormModel?

    var body: some View {
        Group {
            if let model {
                WalletFormContent(model: model, onSaved: onSaved)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = WalletFormModel(mode: mode, service: app.wallets)
        }
    }
}

private struct WalletFormContent: View {
    @Bindable var model: WalletFormModel
    let onSaved: ((Wallet) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $model.type) {
                        ForEach(WalletType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.defaultIconName).tag(type)
                        }
                    }
                }
                .surfaceRows()

                if model.showsCurrencyPicker {
                    Section {
                        Picker("Currency", selection: $model.currency) {
                            ForEach(model.currencyOptions, id: \.self) { currency in
                                Text(verbatim: currencyLabel(currency)).tag(currency)
                            }
                        }
                        .disabled(model.currencyLocked)
                    } footer: {
                        if model.currencyLocked {
                            Text("The currency can't change once the wallet has transactions.")
                        }
                    }
                    .surfaceRows()
                }

                Section {
                    AmountField(text: $model.openingText, currency: model.currency)
                } header: {
                    Text(model.isLiability ? "Amount owed now" : "Opening balance")
                } footer: {
                    Text(model.isLiability
                         ? "What you currently owe on this card. It is recorded as debt, not as an expense."
                         : "Money already in this wallet. It is not counted as income. Leave empty for zero.")
                }
                .surfaceRows()

                Section("Appearance") {
                    HStack {
                        Spacer()
                        IconBadge(systemName: model.iconName, tint: PaletteColor(identifier: model.colorIdentifier).color,
                                  size: .large)
                            .padding(.vertical, Spacing.sm)
                        Spacer()
                    }
                    SymbolPicker(
                        selection: $model.iconName,
                        symbols: SymbolCatalog.wallets,
                        tint: PaletteColor(identifier: model.colorIdentifier).color
                    )
                    PalettePicker(selection: $model.colorIdentifier)
                }
                .surfaceRows()

                Section("Note") {
                    TextField("Optional", text: $model.note, axis: .vertical)
                }
                .surfaceRows()
            }
            .appGroupedStyle()
            .keyboardDismissal()
            .safeAreaInset(edge: .bottom) {
                PrimaryActionBar(title: model.isEditing ? "Save Changes" : "Save Wallet", isEnabled: model.canSave) {
                    if let saved = model.save() {
                        onSaved?(saved)
                        dismiss()
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Wallet" : "New Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .errorAlert(Binding(
                get: { model.failure.map { AlertError($0) } },
                set: { if $0 == nil { model.clearFailure() } }
            ))
        }
    }

    private func currencyLabel(_ currency: CurrencyDefinition) -> String {
        let name = Locale.app.localizedString(forCurrencyCode: currency.code) ?? currency.code
        return "\(currency.code) · \(name)"
    }
}

#Preview(traits: .emptyStore) {
    WalletFormView(mode: .create)
}
