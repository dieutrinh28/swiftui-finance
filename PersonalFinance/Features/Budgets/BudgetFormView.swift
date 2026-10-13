import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Create or edit a budget. State and rules live in `BudgetFormModel`.
struct BudgetFormView: View {
    typealias Mode = BudgetFormModel.Mode

    let mode: Mode

    @Environment(AppContainer.self) private var app
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \Wallet.sortOrder) private var wallets: [Wallet]

    @State private var model: BudgetFormModel?

    var body: some View {
        Group {
            if let model {
                BudgetFormContent(model: model, categories: categories, wallets: wallets)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = BudgetFormModel(mode: mode, service: app.budgets, calendar: app.calendarPolicy)
        }
    }
}

private struct BudgetFormContent: View {
    @Bindable var model: BudgetFormModel
    let categories: [LedgerCategory]
    let wallets: [Wallet]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.name)
                        .textInputAutocapitalization(.words)
                }

                Section("Planned amount per period") {
                    AmountField(text: $model.amountText, currency: model.currency)
                    if CurrencyCatalog.offersChoice(including: model.currency) {
                        Picker("Currency", selection: $model.currency) {
                            ForEach(CurrencyCatalog.pickerOptions(including: model.currency), id: \.self) { currency in
                                Text(currency.code).tag(currency)
                            }
                        }
                    }
                }

                periodSection
                categorySection
                walletSection

                if model.supportsRollover {
                    Section {
                        Toggle("Roll over", isOn: $model.rolloverEnabled)
                    } footer: {
                        Text("Money left at the end of a period is added to the next one; overspending is taken from it.")
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Budget" : "New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save(categories: categories, wallets: wallets) { dismiss() }
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

    private var periodSection: some View {
        Section {
            Picker("Repeats", selection: $model.period) {
                ForEach(BudgetPeriod.allCases, id: \.self) { period in
                    Text(period.displayName).tag(period)
                }
            }
            DatePicker("Starts", selection: $model.startDate, displayedComponents: .date)
            if model.requiresEndDate {
                DatePicker("Ends", selection: $model.endDate, in: model.startDate..., displayedComponents: .date)
            } else {
                Toggle("Stop on a date", isOn: $model.hasEndDate)
                if model.hasEndDate {
                    DatePicker("Last day", selection: $model.endDate, in: model.startDate..., displayedComponents: .date)
                }
            }
        } header: {
            Text("Period")
        } footer: {
            Text("Weeks start on Monday; months and years follow the calendar. The first period begins on the start date.")
        }
    }

    private var categorySection: some View {
        Section {
            ForEach(model.selectableCategories(from: categories)) { category in
                let isSelected = model.selectedCategoryIDs.contains(category.id)
                Button {
                    model.toggleCategory(category)
                } label: {
                    HStack(spacing: Spacing.md) {
                        IconBadge(systemName: category.iconName,
                                  tint: PaletteColor(identifier: category.colorIdentifier).color)
                        Text(category.name)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Expenses in these categories, and their sub-categories, count towards the budget. Income and transfers never do.")
        }
    }

    private var walletSection: some View {
        Section {
            Toggle("Only some wallets", isOn: $model.limitsWallets)
            if model.limitsWallets {
                let selectable = model.selectableWallets(from: wallets)
                if selectable.isEmpty {
                    Text(CurrencyCatalog.offersChoice(including: model.currency)
                         ? "No wallets use \(model.currency.code)."
                         : "No active wallets.")
                        .foregroundStyle(.secondary)
                }
                ForEach(selectable) { wallet in
                    let isSelected = model.selectedWalletIDs.contains(wallet.id)
                    Button {
                        model.toggleWallet(wallet)
                    } label: {
                        HStack {
                            Text(wallet.name).foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        } header: {
            Text("Wallets")
        } footer: {
            if CurrencyCatalog.offersChoice(including: model.currency) {
                Text("Only expenses in \(model.currency.code) count. Spending in other currencies is shown separately, never converted.")
            } else {
                Text("Leave off to count expenses from every wallet.")
            }
        }
    }
}

#Preview(traits: .sampleData) {
    BudgetFormView(mode: .create)
}
