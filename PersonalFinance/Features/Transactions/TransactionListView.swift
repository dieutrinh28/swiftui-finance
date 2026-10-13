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
                    ContentUnavailableView {
                        Label("No transactions yet", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Income, expenses and transfers you record will appear here.")
                    } actions: {
                        Button("Add Transaction") { showingNewTransaction = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if let model {
                    TransactionListContent(model: model, transactions: transactions)
                } else {
                    ProgressView()
                }
            }
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
                    HStack {
                        Label("\(model.query.activeFilterCount) filters on", systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.subheadline)
                        Spacer()
                        Button("Clear") { model.clearFilters() }
                            .font(.subheadline)
                    }
                }
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
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView {
                    Label("No matching transactions", systemImage: "magnifyingglass")
                } description: {
                    Text("Try other words or fewer filters.")
                } actions: {
                    Button("Clear Search and Filters") {
                        model.query.searchText = ""
                        model.clearFilters()
                    }
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
            return String(localized: "\(section.transactions.count) results")
        }
        switch grouping {
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        case .day:
            let calendar = app.calendarPolicy.calendar
            if calendar.isDateInToday(start) { return String(localized: "Today") }
            if calendar.isDateInYesterday(start) { return String(localized: "Yesterday") }
            return start.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        }
    }
}

extension TransactionSort {
    var displayName: String {
        switch self {
        case .newestFirst: String(localized: "Newest first")
        case .oldestFirst: String(localized: "Oldest first")
        case .largestFirst: String(localized: "Largest amount first")
        case .smallestFirst: String(localized: "Smallest amount first")
        }
    }
}

struct TransactionRow: View {
    let transaction: LedgerTransaction
    var showsWallet = true
    /// When shown inside a wallet, transfers are signed from that wallet's point of view.
    var perspective: Wallet? = nil

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(systemName: iconName, tint: tint)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.sm)
            amount
        }
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
            Text("Invalid record")
                .font(.footnote)
                .foregroundStyle(AppColor.expense)
        }
    }

    private var title: String {
        if transaction.kind == .transfer {
            return String(localized: "Transfer")
        }
        return transaction.category?.name ?? transaction.kind?.displayName ?? String(localized: "Unknown")
    }

    private var subtitle: String {
        let detail = transaction.note ?? transaction.merchant
        let wallets: String?
        if transaction.kind == .transfer {
            let from = transaction.transferSource?.wallet?.name ?? "?"
            let to = transaction.transferDestination?.wallet?.name ?? "?"
            wallets = "\(from) → \(to)"
        } else {
            wallets = showsWallet ? transaction.primaryWallet?.name : nil
        }
        return [detail, wallets].compactMap { $0 }.joined(separator: " · ")
    }

    private var iconName: String {
        if transaction.kind == .transfer { return "arrow.left.arrow.right" }
        return transaction.category?.iconName ?? "questionmark.circle"
    }

    private var tint: Color {
        if transaction.kind == .transfer { return AppColor.transfer }
        return transaction.category.map { PaletteColor(identifier: $0.colorIdentifier).color } ?? .gray
    }
}

#Preview("Transactions", traits: .sampleData) {
    TransactionListView()
}

#Preview("Empty", traits: .emptyStore) {
    TransactionListView()
}
