import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Filters for the transaction list: date, type, wallets, categories and amount.
/// Changes apply immediately; the list updates behind the sheet.
struct TransactionFilterView: View {
    @Bindable var model: TransactionListModel

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Wallet.sortOrder) private var wallets: [Wallet]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var limitsPeriod = false
    @State private var period: ReportingPeriod = .thisMonth
    @State private var minimumText = ""
    @State private var maximumText = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Toggle("Only a period", isOn: $limitsPeriod)
                    if limitsPeriod {
                        PeriodPicker(selection: $period)
                    }
                }

                Section("Type") {
                    ForEach(TransactionKind.allCases, id: \.self) { kind in
                        CheckRow(title: kind.displayName, isOn: model.query.kinds.contains(kind)) {
                            toggle(kind, in: \.kinds)
                        }
                    }
                }

                Section("Wallets") {
                    ForEach(wallets) { wallet in
                        CheckRow(title: wallet.isArchived ? "\(wallet.name) (archived)" : wallet.name,
                                 isOn: model.query.walletIDs.contains(wallet.id)) {
                            toggle(wallet.id, in: \.walletIDs)
                        }
                    }
                }

                Section("Categories") {
                    ForEach(categories) { category in
                        CheckRow(title: category.name,
                                 systemImage: category.iconName,
                                 isOn: model.query.categoryIDs.contains(category.id)) {
                            toggle(category.id, in: \.categoryIDs)
                        }
                    }
                }

                Section {
                    TextField("Minimum", text: $minimumText)
                        .keyboardType(.decimalPad)
                    TextField("Maximum", text: $maximumText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Amount")
                } footer: {
                    if CurrencyCatalog.isMultiCurrencyEnabled {
                        Text("Compared in each transaction's own currency.")
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        model.clearFilters()
                        limitsPeriod = false
                        minimumText = ""
                        maximumText = ""
                    }
                    .disabled(model.query.activeFilterCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
            .onChange(of: limitsPeriod) { applyPeriod() }
            .onChange(of: period) { applyPeriod() }
            .onChange(of: minimumText) { model.query.minimumAmount = parse(minimumText) }
            .onChange(of: maximumText) { model.query.maximumAmount = parse(maximumText) }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let current = model.period {
            limitsPeriod = true
            period = current
        }
        let parser = AmountInputParser()
        if let minimum = model.query.minimumAmount { minimumText = parser.editingText(for: money(minimum)) }
        if let maximum = model.query.maximumAmount { maximumText = parser.editingText(for: money(maximum)) }
    }

    private func applyPeriod() {
        try? model.setPeriod(limitsPeriod ? period : nil)
    }

    private func toggle<Value: Hashable>(_ value: Value, in keyPath: WritableKeyPath<TransactionQuery, Set<Value>>) {
        if model.query[keyPath: keyPath].contains(value) {
            model.query[keyPath: keyPath].remove(value)
        } else {
            model.query[keyPath: keyPath].insert(value)
        }
    }

    /// Accepts amounts as typed for the main currency (e.g. "100.000" or "100000" for VND).
    private func parse(_ text: String) -> Decimal? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return try? AmountInputParser().parse(text, currency: CurrencyCatalog.defaultCurrency).majorUnits
    }

    private func money(_ amount: Decimal) -> Money {
        (try? Money.fromMajorUnits(amount, currency: CurrencyCatalog.defaultCurrency)) ?? .zero(CurrencyCatalog.defaultCurrency)
    }
}

/// A tappable row with a checkmark.
private struct CheckRow: View {
    let title: String
    var systemImage: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(Color.primary)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
