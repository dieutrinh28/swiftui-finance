import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Transactions tab: search, filter, sort and group the whole history.
/// The query logic lives in `TransactionListModel` (unit-tested).
struct TransactionListView: View {
    @Query(sort: \LedgerTransaction.date, order: .reverse)
    private var transactions: [LedgerTransaction]

    @Environment(AppContainer.self) private var app
    @State private var model: TransactionListModel?
    @State private var showingNewTransaction = false

    var body: some View {
        NavigationStack(path: app.router.binding(for: .transactions)) {
            Group {
                if transactions.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.rectangle",
                        title: "No transactions yet",
                        message: "Income, expenses and transfers you record will appear here."
                    ) {
                        Button("Add Transaction", systemImage: "plus") { showingNewTransaction = true }
                            .buttonStyle(.appPrimary)
                    }
                    .frame(maxHeight: .infinity)
                } else if let model {
                    TransactionListContent(model: model, transactions: transactions)
                } else {
                    ProgressView()
                }
            }
            .screenBackground()
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTransaction = true
                    } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewTransaction) {
                TransactionFormView(mode: .create(wallet: nil))
            }
            .financeDestinations()
            .onAppear {
                if model == nil {
                    model = TransactionListModel(policy: app.calendarPolicy)
                }
            }
        }
    }
}

private struct TransactionListContent: View {
    @Bindable var model: TransactionListModel
    let transactions: [LedgerTransaction]

    @Environment(AppContainer.self) private var app
    @State private var showingFilters = false

    var body: some View {
        let sections = model.sections(from: transactions)
        List {
            if model.query.activeFilterCount > 0 {
                Section {
                    ActiveFiltersBar(count: model.query.activeFilterCount) {
                        model.clearFilters()
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.xs, bottom: 0, trailing: Spacing.xs))
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.transactions) { transaction in
                        NavigationLink(value: transaction) {
                            TransactionRow(transaction: transaction)
                        }
                    }
                } header: {
                    Text(title(for: section))
                        .font(.label.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
                .surfaceRows()
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)   // day groups sit closer than settings sections
        .appGroupedStyle()
        .overlay {
            if sections.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No matching transactions",
                    message: "Try other words or fewer filters."
                ) {
                    Button("Clear Search and Filters") {
                        model.query.searchText = ""
                        model.clearFilters()
                    }
                    .buttonStyle(.appSecondary)
                }
            }
        }
        .searchable(text: $model.query.searchText, prompt: "Notes, merchants, categories, wallets")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Sort", selection: $model.query.sort) {
                        ForEach(TransactionSort.allCases, id: \.self) { sort in
                            Text(sort.displayName).tag(sort)
                        }
                    }
                    if model.isGroupedByDate {
                        Picker("Group by", selection: $model.grouping) {
                            Text("Day").tag(TransactionListModel.Grouping.day)
                            Text("Month").tag(TransactionListModel.Grouping.month)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingFilters = true
                } label: {
                    Label("Filters", systemImage: model.query.activeFilterCount > 0
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            TransactionFilterView(model: model)
        }
    }

    private func title(for section: TransactionListModel.Section) -> String {
        guard let start = section.start, let grouping = section.grouping else {
            return String(localized: "\(section.transactions.count) results", bundle: .l10n)
        }
        switch grouping {
        case .month:
            return start.formatted(.dateTime.month(.wide).year().locale(.app))
        case .day:
            let calendar = app.calendarPolicy.calendar
            if calendar.isDateInToday(start) { return String(localized: "Today", bundle: .l10n) }
            if calendar.isDateInYesterday(start) { return String(localized: "Yesterday", bundle: .l10n) }
            return start.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(.app))
        }
    }
}

/// Shows that filters are narrowing the list, with a one-tap way out.
private struct ActiveFiltersBar: View {
    let count: Int
    let clear: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Label("\(count) filter(s) on", systemImage: "line.3.horizontal.decrease")
                .font(.label.weight(.medium))
                .foregroundStyle(AppColor.accent)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(AppColor.softBlue, in: Capsule())
            Spacer(minLength: Spacing.sm)
            Button("Clear All", action: clear)
                .font(.label.weight(.medium))
                .frame(minHeight: 44)
        }
    }
}

extension TransactionSort {
    var displayName: String {
        switch self {
        case .newestFirst: String(localized: "Newest first", bundle: .l10n)
        case .oldestFirst: String(localized: "Oldest first", bundle: .l10n)
        case .largestFirst: String(localized: "Largest amount first", bundle: .l10n)
        case .smallestFirst: String(localized: "Smallest amount first", bundle: .l10n)
        }
    }
}

/// One transaction: category icon, title, one line of detail and the signed
/// amount, right-aligned so amounts line up down the list. A sub-category's
/// parent leads the detail line ("Coffee" / "Food & Drinks · Momo"). The amount never
/// truncates; the title gives way first.
struct TransactionRow: View {
    let transaction: LedgerTransaction
    var showsWallet = true
    /// Adds the day ("12 Oct") to the detail line, for lists not grouped by date.
    var showsDate = false
    /// When shown inside a wallet, transfers are signed from that wallet's point of view.
    var perspective: Wallet? = nil

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(systemName: iconName, tint: tint)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }
            // In a List, separators start under the text rather than under the icon.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: Spacing.sm)
            amount
                .layoutPriority(1)
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var amount: some View {
        if transaction.kind == .transfer,
           let perspective,
           let entry = transaction.entry(in: perspective),
           let magnitude = entry.magnitude {
            MoneyText(money: magnitude, tone: entry.amountMinorUnits < 0 ? .transferOut : .transferIn)
        } else if let amount = transaction.displayAmount, let kind = transaction.kind {
            MoneyText(money: amount, tone: kind.tone)
        } else {
            Label("Invalid record", systemImage: "exclamationmark.triangle")
                .font(.meta)
                .foregroundStyle(AppColor.negative)
        }
    }

    private var title: String {
        if transaction.kind == .transfer {
            return String(localized: "Transfer", bundle: .l10n)
        }
        return transaction.category?.name ?? transaction.kind?.displayName ?? String(localized: "Unknown", bundle: .l10n)
    }

    private var subtitle: String {
        let date = showsDate ? transaction.date.formatted(.dateTime.day().month(.abbreviated).locale(.app)) : nil
        let parent = transaction.kind == .transfer ? nil : transaction.category?.parent?.name
        let irregular = transaction.isIrregular ? String(localized: "Irregular", bundle: .l10n) : nil
        let detail = transaction.note ?? transaction.merchant
        let wallets: String?
        if transaction.kind == .transfer {
            let from = transaction.transferSource?.wallet?.name ?? "?"
            let to = transaction.transferDestination?.wallet?.name ?? "?"
            wallets = "\(from) → \(to)"
        } else {
            wallets = showsWallet ? transaction.primaryWallet?.name : nil
        }
        return [date, parent, irregular, detail, wallets].compactMap { $0 }.joined(separator: " · ")
    }

    private var iconName: String {
        if transaction.kind == .transfer { return "arrow.left.arrow.right" }
        return transaction.category?.iconName ?? "questionmark.circle"
    }

    private var tint: Color {
        if transaction.kind == .transfer { return AppColor.transfer }
        return PaletteColor(identifier: transaction.category?.colorIdentifier ?? "gray").color
    }
}

#Preview("Transactions", traits: .sampleData) {
    TransactionListView()
}

#Preview("Empty", traits: .emptyStore) {
    TransactionListView()
}
