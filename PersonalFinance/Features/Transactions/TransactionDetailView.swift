import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

struct TransactionDetailView: View {
    let transaction: LedgerTransaction

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var error: AlertError?

    var body: some View {
        // The transaction may be deleted while this screen is still animating away.
        if transaction.isDeleted || transaction.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        IconBadge(systemName: headerIcon, tint: headerTint, size: .large)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(headerTitle)
                                .font(.cardTitle)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(transaction.kind?.displayName ?? String(localized: "Unknown", bundle: .l10n))
                                .font(.meta)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    if let amount = transaction.displayAmount, let kind = transaction.kind {
                        MoneyText(money: amount, tone: kind.tone, font: .amountHero)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else {
                        Label("This record is incomplete and can't be shown.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppColor.negative)
                    }
                    Text(transaction.date.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(.app)))
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.vertical, Spacing.sm)
                .accessibilityElement(children: .combine)
            }
            .highlightedRows()

            if transaction.kind == .transfer {
                transferSection
            }

            Section {
                if let category = transaction.category {
                    NavigationLink(value: category) {
                        LabeledContent("Category") {
                            InlineLabel(verbatim: category.path, systemImage: category.iconName)
                        }
                    }
                }
                if transaction.kind != .transfer, let wallet = transaction.primaryWallet {
                    NavigationLink(value: wallet) {
                        LabeledContent("Wallet", value: wallet.name)
                    }
                }
                if transaction.isIrregular {
                    LabeledContent("Spending") {
                        InlineLabel("Irregular, not counted", systemImage: "sparkles")
                    }
                }
                if let merchant = transaction.merchant {
                    LabeledContent("Merchant", value: merchant)
                }
                if let note = transaction.note {
                    LabeledContent("Note", value: note)
                }
            }
            .surfaceRows()

            Section {
                LabeledContent("Created", value: transaction.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.app)))
                if transaction.updatedAt != transaction.createdAt {
                    LabeledContent("Last edited", value: transaction.updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.app)))
                }
            }
            .font(.meta)
            .foregroundStyle(AppColor.textSecondary)
            .surfaceRows()

            if !transaction.isEditable {
                Section {
                    Label("This transaction involves an archived wallet. Restore the wallet to edit or delete it.",
                          systemImage: "archivebox")
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .surfaceRows()
            }
        }
        .appGroupedStyle()
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if transaction.isEditable {
                ToolbarItem(placement: .topBarTrailing) {  // not .secondaryAction: iOS nests that in its own "…" overflow menu
                    Menu {
                        Button("Edit Transaction", systemImage: "pencil") { showingEdit = true }
                        Button("Delete Transaction", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            TransactionFormView(mode: .edit(transaction))
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Transaction", role: .destructive, action: delete)
        } message: {
            Text("Wallet balances will be updated. This can't be undone.")
        }
        .errorAlert($error)
    }

    @ViewBuilder
    private var transferSection: some View {
        Section("Transfer") {
            if let source = transaction.transferSource, let wallet = source.wallet {
                NavigationLink(value: wallet) {
                    LabeledContent("From") {
                        VStack(alignment: .trailing) {
                            Text(wallet.name)
                            if let sent = source.magnitude {
                                MoneyText(money: sent, tone: .transferOut, font: .amountDetail)
                            }
                        }
                    }
                }
            }
            if let destination = transaction.transferDestination, let wallet = destination.wallet {
                NavigationLink(value: wallet) {
                    LabeledContent("To") {
                        VStack(alignment: .trailing) {
                            Text(wallet.name)
                            if let received = destination.magnitude {
                                MoneyText(money: received, tone: .transferIn, font: .amountDetail)
                            }
                        }
                    }
                }
            }
            if let rate = transaction.exchangeRate,
               let from = transaction.transferSource?.currencyCode,
               let to = transaction.transferDestination?.currencyCode {
                LabeledContent("Exchange rate", value: "1 \(from) = \(rate.formatted(.number.precision(.fractionLength(0...6)).locale(.app))) \(to)")
            }
            Text("Transfers move money between your wallets. They are not counted as income, expenses or budget spending.")
                .font(.meta)
                .foregroundStyle(AppColor.textSecondary)
        }
        .surfaceRows()
    }

    private var headerTitle: String {
        if transaction.kind == .transfer { return String(localized: "Transfer", bundle: .l10n) }
        return transaction.category?.name ?? transaction.kind?.displayName ?? String(localized: "Unknown", bundle: .l10n)
    }

    private var headerIcon: String {
        if transaction.kind == .transfer { return "arrow.left.arrow.right" }
        return transaction.category?.iconName ?? "questionmark.circle"
    }

    private var headerTint: Color {
        if transaction.kind == .transfer { return AppColor.transfer }
        return PaletteColor(identifier: transaction.category?.colorIdentifier ?? "gray").color
    }

    private func delete() {
        do {
            try app.transactions.delete(transaction)
            dismiss()
        } catch {
            self.error = AlertError(error, title: String(localized: "Couldn't Delete", bundle: .l10n))
        }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query(sort: \LedgerTransaction.date, order: .reverse) var transactions: [LedgerTransaction]
    NavigationStack {
        if let transaction = transactions.first {
            TransactionDetailView(transaction: transaction)
                .financeDestinations()
        }
    }
}
