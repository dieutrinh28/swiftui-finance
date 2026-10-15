import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Create or edit a recurring income, expense or transfer. Logic lives in `RecurringFormModel`.
struct RecurringFormView: View {
    typealias Mode = RecurringFormModel.Mode
    let mode: Mode

    @Environment(AppContainer.self) private var app
    /// Every wallet; the form offers only `WalletChoices.selectable` (archived ones never).
    @Query(sort: \Wallet.sortOrder)
    private var wallets: [Wallet]
    @State private var model: RecurringFormModel?

    var body: some View {
        Group {
            if let model {
                RecurringFormContent(model: model, wallets: wallets)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            let newModel = RecurringFormModel(mode: mode, service: app.recurring, policy: app.calendarPolicy)
            newModel.selectDefaultWalletIfNeeded(from: wallets)
            model = newModel
        }
    }
}

private struct RecurringFormContent: View {
    @Bindable var model: RecurringFormModel
    let wallets: [Wallet]

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $model.kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Income").tag(TransactionKind.income)
                        Text("Transfer").tag(TransactionKind.transfer)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if model.loadFailure != nil {
                    Section {
                        ReadFailureLabel("This item's wallet or category couldn't be read, so it can't be saved now.")
                    }
                    .surfaceRows()
                }

                Section {
                    TextField("Name, e.g. Rent or Salary", text: $model.name)
                        .textInputAutocapitalization(.words)
                }
                .surfaceRows()

                Section(model.isTransfer ? "Amount sent" : "Amount") {
                    if let currency = model.currency {
                        AmountField(text: $model.amountText, currency: currency,
                                    tone: model.isTransfer ? .transferOut : model.kind.tone)
                    } else {
                        Text("Choose a wallet to enter the amount.").foregroundStyle(AppColor.textSecondary)
                    }
                }
                .surfaceRows()

                Section {
                    Picker(model.isTransfer ? "From" : "Wallet", selection: $model.wallet) {
                        if model.wallet == nil { Text("Choose").tag(Wallet?.none) }
                        ForEach(model.walletChoices(from: wallets)) { wallet in
                            Text(wallet.nameWithCurrency).tag(Optional(wallet))
                        }
                    }
                    if model.isTransfer {
                        Picker("To", selection: $model.destination) {
                            Text("Choose").tag(Wallet?.none)
                            ForEach(model.destinationChoices(from: wallets)) { wallet in
                                Text(wallet.nameWithCurrency).tag(Optional(wallet))
                            }
                        }
                    } else {
                        NavigationLink {
                            CategoryPickerView(type: model.requiredCategoryType, selection: $model.category)
                        } label: {
                            CategoryFieldLabel(category: model.category)
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if !model.archivedWalletNames.isEmpty {
                            Text("\(model.archivedWalletNames.formatted(.list(type: .and).locale(.app))) is archived, so it is no longer offered. Choose another wallet; until then nothing becomes due.")
                        }
                        if model.isTransfer {
                            Text(model.needsReceivedAmount
                                 ? "The wallets use different currencies, so enter the amount that arrives. You can change both when recording."
                                 : "Moves money between your wallets. Transfers are not income or spending.")
                        }
                    }
                }
                .surfaceRows()

                if model.needsReceivedAmount, let currency = model.destination?.currency {
                    Section("Amount received") {
                        AmountField(text: $model.receivedText, currency: currency, tone: .transferIn)
                    }
                    .surfaceRows()
                }

                Section {
                    Picker("Repeats", selection: $model.frequency) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Stepper(value: $model.interval, in: RecurrenceRules.intervalRange) {
                        Text(model.frequency.describe(interval: model.interval))
                    }
                    DatePicker("First due", selection: $model.startDate, displayedComponents: .date)
                    Toggle("Ends", isOn: $model.hasEndDate)
                    if model.hasEndDate {
                        DatePicker("Last due", selection: $model.endDate, in: model.startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    if let next = model.nextOccurrence {
                        Text("Next due \(next.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(.app))). Monthly items on the 29th–31st fall on the last day of shorter months.")
                    } else {
                        Text("No upcoming occurrences.")
                    }
                }
                .surfaceRows()

                Section {
                    Toggle("Remind me", isOn: $model.reminderEnabled)
                        .tint(AppColor.accent)
                    if model.reminderEnabled {
                        DatePicker("At", selection: $model.reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(notificationsDenied
                         ? "Notifications are turned off for this app. You can allow them in iOS Settings; due items still appear when you open the app."
                         : "A notification on the due day. iOS decides when it is delivered; the transaction is only recorded when you confirm it in the app.")
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
                PrimaryActionBar(title: model.isEditing ? "Save Changes" : "Save Recurring", isEnabled: model.canSave) {
                    if model.save() { dismiss() }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Recurring" : "New Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: model.reminderEnabled) { _, enabled in
                guard enabled else { return }
                Task { notificationsDenied = !(await app.reminders.requestAuthorizationIfNeeded()) }
            }
            .errorAlert(Binding(
                get: { model.failure.map { AlertError($0) } },
                set: { if $0 == nil { model.clearFailure() } }
            ))
        }
    }
}

#Preview(traits: .sampleData) {
    RecurringFormView(mode: .create)
}
