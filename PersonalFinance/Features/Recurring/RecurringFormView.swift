import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Create or edit a recurring income or expense. Logic lives in `RecurringFormModel`.
struct RecurringFormView: View {
    typealias Mode = RecurringFormModel.Mode
    let mode: Mode

    @Environment(AppContainer.self) private var app
    @Query(filter: #Predicate<Wallet> { $0.archivedAt == nil }, sort: \Wallet.sortOrder)
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
                    TextField("Name, e.g. Rent or Salary", text: $model.name)
                    Picker("Type", selection: $model.kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Income").tag(TransactionKind.income)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Amount") {
                    if let currency = model.currency {
                        AmountField(text: $model.amountText, currency: currency, tone: model.kind.tone)
                    } else {
                        Text("Choose a wallet to enter the amount.").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Wallet", selection: $model.wallet) {
                        if model.wallet == nil { Text("Choose").tag(Wallet?.none) }
                        ForEach(wallets) { wallet in
                            Text(wallet.nameWithCurrency).tag(Optional(wallet))
                        }
                    }
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
                        Text("Next due \(next.formatted(date: .complete, time: .omitted)). Monthly items on the 29th–31st fall on the last day of shorter months.")
                    } else {
                        Text("No upcoming occurrences.")
                    }
                }

                Section {
                    Toggle("Remind me", isOn: $model.reminderEnabled)
                    if model.reminderEnabled {
                        DatePicker("At", selection: $model.reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(notificationsDenied
                         ? "Notifications are turned off for this app. You can allow them in iOS Settings; due items still appear when you open the app."
                         : "A notification on the due day. iOS decides when it is delivered; the transaction is only recorded when you confirm it in the app.")
                }

                Section("Note") {
                    TextField("Optional", text: $model.note, axis: .vertical)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Recurring" : "New Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save() { dismiss() }
                    }
                    .disabled(!model.canSave)
                }
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
