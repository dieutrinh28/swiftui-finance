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
                .surfaceRows()

                Section("Type") {
                    ForEach(TransactionKind.allCases, id: \.self) { kind in
                        CheckRow(title: kind.displayName, isOn: model.query.kinds.contains(kind)) {
                            toggle(kind, in: \.kinds)
                        }
                    }
                }
                .surfaceRows()

                Section("Wallets") {
                    ForEach(WalletChoices.selectable(from: wallets)) { wallet in
                        CheckRow(title: wallet.name,
                                 isOn: model.query.walletIDs.contains(wallet.id)) {
                            toggle(wallet.id, in: \.walletIDs)
                        }
                    }
                }
                .surfaceRows()

                ForEach([CategoryType.expense, .income], id: \.self) { type in
                    let matching = categories.filter { $0.type == type }.inHierarchy()
                    if !matching.isEmpty {
                        Section {
                            ForEach(matching, id: \.category.id) { item in
                                CheckRow(title: item.category.name,
                                         systemImage: item.category.iconName,
                                         level: item.level,
                                         isOn: model.query.categoryIDs.contains(item.category.id)) {
                                    toggle(item.category.id, in: \.categoryIDs)
                                }
                            }
                        } header: {
                            Text(type == .expense ? "Expense categories" : "Income categories")
                        } footer: {
                            if type == .expense {
                                Text("Choosing a category also shows its sub-categories.")
                            }
                        }
                        .surfaceRows()
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
                .surfaceRows()
            }
            .appGroupedStyle()
            .keyboardDismissal()
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
                // convention-ok: C4 filters apply immediately; Done only closes the sheet
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
        // A wallet archived since it was chosen is no longer listed, so it can't stay an invisible filter.
        model.query.walletIDs.subtract(wallets.filter(\.isArchived).map(\.id))
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
    /// 1 for a sub-category, indented under its parent.
    var level = 0
    let isOn: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var indent = 28

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
                        .font(.checkmark)
                        .foregroundStyle(AppColor.accent)
                }
            }
            .foregroundStyle(AppColor.textPrimary)
            .padding(.leading, CGFloat(level) * indent)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
