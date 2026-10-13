import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Quick entry for income, expenses and transfers:
/// type → amount → wallet(s) and category → optional details → Save.
///
/// All form state and logic live in `TransactionFormModel` (unit-tested in
/// FinanceKit). This view only creates the model, renders it and handles
/// focus, sheets and dismissal.
struct TransactionFormView: View {
    typealias Mode = TransactionFormModel.Mode

    let mode: Mode

    @Environment(AppContainer.self) private var app
    @Query(filter: #Predicate<Wallet> { $0.archivedAt == nil }, sort: \Wallet.sortOrder)
    private var wallets: [Wallet]

    @State private var model: TransactionFormModel?

    var body: some View {
        Group {
            if let model {
                TransactionFormContent(model: model, wallets: wallets)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            let newModel = TransactionFormModel(mode: mode, service: app.transactions)
            newModel.selectDefaultWalletIfNeeded(from: wallets)
            model = newModel
        }
    }
}

private struct TransactionFormContent: View {
    @Bindable var model: TransactionFormModel
    let wallets: [Wallet]

    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @State private var showingNewWallet = false

    var body: some View {
        NavigationStack {
            Form {
                if model.availableKinds.count > 1 {
                    Section {
                        Picker("Type", selection: $model.kind) {
                            ForEach(model.availableKinds, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section(model.isTransfer ? "Amount sent" : "Amount") {
                    if let currency = model.currency {
                        AmountField(text: $model.amountText, currency: currency,
                                    tone: model.isTransfer ? .transferOut : model.kind.tone)
                            .focused($amountFocused)
                    } else {
                        Text("Choose a wallet to enter the amount.")
                            .foregroundStyle(.secondary)
                    }
                }

                if wallets.isEmpty {
                    Section {
                        Button("Create a Wallet First") { showingNewWallet = true }
                    }
                } else if model.isTransfer {
                    transferSection
                } else {
                    cashFlowSection
                }

                Section("Details") {
                    DatePicker("Date", selection: $model.date)
                    TextField("Note", text: $model.note, axis: .vertical)
                    if !model.isTransfer {
                        TextField("Merchant or payee", text: $model.merchant)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save() { dismiss() }
                    }
                    .disabled(!model.canSave)
                }
            }
            .onAppear {
                if !model.isEditing { amountFocused = true }
            }
            .sheet(isPresented: $showingNewWallet) {
                WalletFormView(mode: .create) { created in model.wallet = created }
            }
            .errorAlert(Binding(
                get: { model.failure.map { AlertError($0) } },
                set: { if $0 == nil { model.clearFailure() } }
            ))
        }
    }

    private var title: String {
        switch (model.isEditing, model.isTransfer) {
        case (false, false): String(localized: "New Transaction")
        case (false, true): String(localized: "New Transfer")
        case (true, false): String(localized: "Edit Transaction")
        case (true, true): String(localized: "Edit Transfer")
        }
    }

    // MARK: Sections

    private var cashFlowSection: some View {
        Section {
            walletPicker("Wallet", selection: $model.wallet)

            NavigationLink {
                CategoryPickerView(type: model.requiredCategoryType, selection: $model.category)
            } label: {
                LabeledContent("Category") {
                    if let category = model.category {
                        Label(category.name, systemImage: category.iconName)
                    } else {
                        Text("Required")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var transferSection: some View {
        Section {
            walletPicker("From", selection: $model.wallet)
            walletPicker("To", selection: $model.destinationWallet)
        } footer: {
            Text("A transfer moves money between your own wallets. It is not income or an expense.")
        }

        if model.needsReceivedAmount, let destinationCurrency = model.destinationCurrency {
            Section {
                AmountField(text: $model.receivedAmountText, currency: destinationCurrency, tone: .transferIn)
            } header: {
                Text("Amount received")
            } footer: {
                if let rate = model.impliedExchangeRate, let source = model.currency {
                    Text("1 \(source.code) = \(rate.formatted(.number.precision(.fractionLength(0...6)))) \(destinationCurrency.code). The app never converts currencies on its own.")
                } else {
                    Text("The wallets use different currencies. Enter exactly what arrived; the app never converts on its own.")
                }
            }
        }
    }

    private func walletPicker(_ title: LocalizedStringKey, selection: Binding<Wallet?>) -> some View {
        Picker(title, selection: selection) {
            if selection.wrappedValue == nil {
                Text("Choose").tag(Wallet?.none)
            }
            ForEach(wallets) { wallet in
                Text(wallet.nameWithCurrency).tag(Optional(wallet))
            }
        }
    }
}

#Preview("New", traits: .sampleData) {
    TransactionFormView(mode: .create(wallet: nil))
}

#Preview("No wallets", traits: .emptyStore) {
    TransactionFormView(mode: .create(wallet: nil))
}
