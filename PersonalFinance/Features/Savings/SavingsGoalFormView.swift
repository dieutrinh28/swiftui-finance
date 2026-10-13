import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Create (`goal == nil`) or edit a savings goal. Logic lives in `SavingsGoalFormModel`.
struct SavingsGoalFormView: View {
    let goal: SavingsGoal?

    @Environment(AppContainer.self) private var app
    @Query(filter: #Predicate<Wallet> { $0.archivedAt == nil }, sort: \Wallet.sortOrder)
    private var wallets: [Wallet]
    @State private var model: SavingsGoalFormModel?

    var body: some View {
        Group {
            if let model {
                SavingsGoalFormContent(model: model, wallets: wallets)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = SavingsGoalFormModel(
                mode: goal.map { .edit($0) } ?? .create,
                service: app.savings,
                policy: app.calendarPolicy
            )
        }
    }
}

private struct SavingsGoalFormContent: View {
    @Bindable var model: SavingsGoalFormModel
    let wallets: [Wallet]

    @Environment(\.dismiss) private var dismiss

    private static let symbols = ["target", "cross.case", "airplane", "laptopcomputer", "graduationcap", "house",
                                  "car", "gift", "heart", "star", "banknote", "figure.2.and.child.holdinghands"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Emergency fund", text: $model.name)
                        .textInputAutocapitalization(.sentences)
                }
                targetSection
                Section {
                    Picker("Kept in", selection: $model.linkedWallet) {
                        Text("Not specified").tag(Wallet?.none)
                        ForEach(model.availableWallets(from: wallets)) { wallet in
                            Text(wallet.name).tag(Optional(wallet))
                        }
                    }
                } footer: {
                    Text("Optional. Shows where the money is kept and warns if goals add up to more than that wallet holds. It never changes the wallet.")
                }
                Section("Appearance") {
                    SymbolPicker(selection: $model.iconName, symbols: Self.symbols,
                                 tint: PaletteColor(identifier: model.colorIdentifier).color)
                    PalettePicker(selection: $model.colorIdentifier)
                }
                Section("Note") {
                    TextField("Optional", text: $model.note, axis: .vertical)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Goal" : "New Goal")
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
            .errorAlert(Binding(
                get: { model.failure.map { AlertError($0) } },
                set: { if $0 == nil { model.clearFailure() } }
            ))
        }
    }

    private var targetSection: some View {
        Section {
            AmountField(text: $model.targetText, currency: model.currency)
            if model.showsCurrencyPicker {
                Picker("Currency", selection: $model.currency) {
                    ForEach(model.currencyOptions, id: \.self) { Text($0.code).tag($0) }
                }
                .disabled(model.currencyLocked)
            }
            Toggle("Target date", isOn: $model.hasTargetDate)
            if model.hasTargetDate {
                DatePicker("Reach by", selection: $model.targetDate, in: model.earliestTargetDate...,
                           displayedComponents: .date)
            }
            if let estimate = model.estimate, let monthly = estimate.suggestedMonthly {
                LabeledContent("Per month") {
                    MoneyText(money: monthly, tone: .neutral)
                }
            }
        } header: {
            Text("Target")
        } footer: {
            if model.showsCurrencyPicker && model.currencyLocked {
                Text("The currency can't change once money has been set aside for this goal.")
            } else if let estimate = model.estimate {
                if estimate.isReached {
                    Text("Already reached with what is set aside.")
                } else if let months = estimate.monthsLeft, months > 0 {
                    Text("Set aside about this much each month for \(months) month(s) to reach it on time.")
                }
            }
        }
    }
}

/// Add money to a goal, or take some out.
struct ContributionFormView: View {
    let goal: SavingsGoal
    let isWithdrawal: Bool

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var error: AlertError?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let currency = goal.currency {
                        AmountField(text: $amountText, currency: currency, tone: isWithdrawal ? .transferOut : .transferIn)
                            .focused($focused)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note", text: $note)
                } footer: {
                    Text(isWithdrawal
                         ? "Lowers the amount set aside for this goal. No wallet balance changes."
                         : "Raises the amount set aside for this goal. No wallet balance changes.")
                }
            }
            .navigationTitle(isWithdrawal ? "Take Money Out" : "Add Money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear { focused = true }
            .errorAlert($error)
        }
        .presentationDetents([.medium, .large])
    }

    private var canSave: Bool {
        guard let currency = goal.currency,
              let amount = try? AmountInputParser().parse(amountText, currency: currency)
        else { return false }
        return amount.isPositive
    }

    private func save() {
        guard let currency = goal.currency else { return }
        do {
            try app.savings.addEntry(
                to: goal,
                amount: try AmountInputParser().parse(amountText, currency: currency),
                isWithdrawal: isWithdrawal,
                date: date,
                note: note
            )
            dismiss()
        } catch {
            self.error = AlertError(error)
        }
    }
}
