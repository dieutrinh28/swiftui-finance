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

/// "80 %" in the user's locale, for a budget alert threshold.
enum BudgetAlertLevel {
    static func text(_ threshold: Int) -> String {
        (Double(threshold) / 100).formatted(.percent.precision(.fractionLength(0)).locale(.app))
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
                .surfaceRows()

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
                .surfaceRows()

                periodSection
                categorySection
                walletSection

                if model.supportsRollover {
                    Section {
                        Toggle("Roll over", isOn: $model.rolloverEnabled)
                    } footer: {
                        Text("Money left at the end of a period is added to the next one; overspending is taken from it.")
                    }
                    .surfaceRows()
                }

                alertSection
            }
            .appGroupedStyle()
            .keyboardDismissal()
            .safeAreaInset(edge: .bottom) {
                PrimaryActionBar(title: model.isEditing ? "Save Changes" : "Save Budget", isEnabled: model.canSave) {
                    if model.save(categories: categories, wallets: wallets) { dismiss() }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Budget" : "New Budget")
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
        .surfaceRows()
    }

    /// Off, or any of 50/80/90/100 % of the available amount.
    private var alertSection: some View {
        Section {
            ForEach(BudgetAlertRules.allowedThresholds, id: \.self) { threshold in
                let isSelected = model.alertThresholds.contains(threshold)
                Button {
                    model.toggleAlert(threshold)
                } label: {
                    HStack {
                        Text(BudgetAlertLevel.text(threshold))
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text(model.alertThresholds.isEmpty
                 ? "No alerts for this budget."
                 : "You get a notification when spending reaches each selected share of the budget, once per period. Budget alerts must also be on in Notifications.")
        }
        .surfaceRows()
    }

    private var categorySection: some View {
        Section {
            ForEach(model.selectableCategories(from: categories).inHierarchy(), id: \.category.id) { item in
                let category = item.category
                let isSelected = model.selectedCategoryIDs.contains(category.id)
                Button {
                    model.toggleCategory(category)
                } label: {
                    HStack(spacing: Spacing.md) {
                        IconBadge(systemName: category.iconName,
                                  tint: PaletteColor(identifier: category.colorIdentifier).color,
                                  size: item.level > 0 ? .small : .regular)
                            .padding(.leading, CGFloat(item.level) * 28)
                        Text(verbatim: category.name)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.selectionCircle)
                            .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Expenses in these categories, and their sub-categories, count towards the budget. Income and transfers never do.")
        }
        .surfaceRows()
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
                        .foregroundStyle(AppColor.textSecondary)
                }
                ForEach(selectable) { wallet in
                    let isSelected = model.selectedWalletIDs.contains(wallet.id)
                    Button {
                        model.toggleWallet(wallet)
                    } label: {
                        HStack {
                            Text(wallet.name).foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        } header: {
            Text("Wallets")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if CurrencyCatalog.offersChoice(including: model.currency) {
                    Text("Only expenses in \(model.currency.code) count. Spending in other currencies is shown separately, never converted.")
                } else {
                    Text("Leave off to count expenses from every wallet.")
                }
                let archived = model.limitsWallets ? model.archivedSelectedWallets(from: wallets) : []
                if !archived.isEmpty {
                    Text("Also counts past spending in \(archived.map(\.name).formatted(.list(type: .and).locale(.app))) (archived).")
                }
            }
        }
        .surfaceRows()
    }
}

#Preview(traits: .sampleData) {
    BudgetFormView(mode: .create)
}
