import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Create (`goal == nil`) or edit a savings goal. Logic lives in `SavingsGoalFormModel`.
struct SavingsGoalFormView: View {
    let goal: SavingsGoal?

    @Environment(AppContainer.self) private var app
    /// Every wallet; the form offers only `WalletChoices.selectable` (archived ones never).
    @Query(sort: \Wallet.sortOrder)
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
                if model.loadFailure != nil {
                    Section {
                        ReadFailureLabel("The goal's wallet couldn't be read, so it can't be saved now.")
                    }
                    .surfaceRows()
                }
                Section {
                    TextField("Name, e.g. Emergency fund", text: $model.name)
                        .textInputAutocapitalization(.sentences)
                }
                .surfaceRows()
                targetSection
                Section {
                    Picker("Kept in", selection: $model.linkedWallet) {
                        Text("Not specified").tag(Wallet?.none)
                        ForEach(model.availableWallets(from: wallets)) { wallet in
                            Text(wallet.name).tag(Optional(wallet))
                        }
                    }
                } footer: {
                    if let archived = model.archivedWalletName, model.linkedWallet == nil {
                        Text("\(archived) is archived, so it is no longer offered. Saving removes it from this goal unless you choose another wallet.")
                    } else {
                        Text("Optional. Shows where the money is kept and warns if goals add up to more than that wallet holds. It never changes the wallet.")
                    }
                }
                .surfaceRows()
                Section("Appearance") {
                    HStack {
                        Spacer()
                        IconBadge(systemName: model.iconName,
                                  tint: PaletteColor(identifier: model.colorIdentifier).color, size: .large)
                            .padding(.vertical, Spacing.sm)
                        Spacer()
                    }
                    SymbolPicker(selection: $model.iconName, symbols: Self.symbols,
                                 tint: PaletteColor(identifier: model.colorIdentifier).color)
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
                PrimaryActionBar(title: model.isEditing ? "Save Changes" : "Save Goal", isEnabled: model.canSave) {
                    if model.save() { dismiss() }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
        .surfaceRows()
    }
}

/// Add money to a goal, or take some out. Logic lives in `ContributionFormModel`.
struct ContributionFormView: View {
    let goal: SavingsGoal
    let isWithdrawal: Bool

    @Environment(AppContainer.self) private var app
    @State private var model: ContributionFormModel?

    var body: some View {
        Group {
            if let model {
                ContributionFormContent(model: model)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = ContributionFormModel(goal: goal, isWithdrawal: isWithdrawal, service: app.savings)
        }
    }
}

private struct ContributionFormContent: View {
    @Bindable var model: ContributionFormModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let currency = model.currency {
                        AmountField(text: $model.amountText, currency: currency,
                                    tone: model.isWithdrawal ? .transferOut : .transferIn)
                            .focused($focused)
                    }
                    DatePicker("Date", selection: $model.date, displayedComponents: .date)
                    TextField("Note", text: $model.note)
                } footer: {
                    Text(model.isWithdrawal
                         ? "Lowers the amount set aside for this goal. No wallet balance changes."
                         : "Raises the amount set aside for this goal. No wallet balance changes.")
                }
                .surfaceRows()
            }
            .appGroupedStyle()
            .keyboardDismissal()
            .safeAreaInset(edge: .bottom) {
                PrimaryActionBar(title: model.isWithdrawal ? "Take Money Out" : "Add Money",
                                 systemImage: model.isWithdrawal ? "minus" : "plus",
                                 isEnabled: model.canSave) {
                    if model.save() { dismiss() }
                }
            }
            .navigationTitle(model.isWithdrawal ? "Take Money Out" : "Add Money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { focused = true }
            .errorAlert(Binding(
                get: { model.failure.map { AlertError($0) } },
                set: { if $0 == nil { model.clearFailure() } }
            ))
        }
        .presentationDetents([.medium, .large])
    }
}
