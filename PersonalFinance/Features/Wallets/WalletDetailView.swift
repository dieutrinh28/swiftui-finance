import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// A wallet's balance, opening balance and transaction history.
struct WalletDetailView: View {
    let wallet: Wallet

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingNewTransaction = false
    @State private var confirmingArchive = false
    @State private var confirmingDelete = false
    @State private var error: AlertError?

    var body: some View {
        // The wallet may be deleted while this screen is still animating away.
        if wallet.isDeleted || wallet.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                header
            }
            .highlightedRows()

            Section("Transactions") {
                let history = wallet.transactionsNewestFirst
                if history.isEmpty {
                    Text("No transactions in this wallet yet.")
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(history) { transaction in
                        NavigationLink(value: transaction) {
                            TransactionRow(transaction: transaction, showsWallet: false, showsDate: true,
                                           perspective: wallet)
                        }
                    }
                }
            }
            .surfaceRows()
        }
        .appGroupedStyle()
        .navigationTitle(wallet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showingEdit) {
            WalletFormView(mode: .edit(wallet))
        }
        .sheet(isPresented: $showingNewTransaction) {
            TransactionFormView(mode: .create(wallet: wallet))
        }
        .confirmationDialog("Archive \(wallet.name)?", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("Archive Wallet", action: archive)
        } message: {
            Text("The wallet and its history are kept, but it is hidden when adding transactions and becomes read-only.")
        }
        .confirmationDialog("Delete \(wallet.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Wallet", role: .destructive, action: delete)
        } message: {
            Text("This wallet has no transactions. This can't be undone.")
        }
        .errorAlert($error)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                IconBadge(systemName: wallet.iconName,
                          tint: PaletteColor(identifier: wallet.colorIdentifier).color, size: .large)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(wallet.name)
                        .font(.cardTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(wallet.typeWithCurrency)
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(wallet.type.accountClass == .liability ? "Current balance (below zero = owed)" : "Current balance")
                    .font(.label)
                    .foregroundStyle(AppColor.textSecondary)
                WalletBalanceText(wallet: wallet, font: .amountHero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            if let opening = wallet.openingBalance {
                HStack {
                    Text("Opening balance")
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    MoneyText(money: opening, font: .amountDetail)
                }
                .font(.label)
                .accessibilityElement(children: .combine)
            }
            if wallet.isArchived {
                NoticeBanner(systemImage: "archivebox",
                             title: "Archived",
                             message: "Restore this wallet to add or change transactions.",
                             tone: .attention)
            }
            if let note = wallet.note {
                Text(note)
                    .font(.meta)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !wallet.isArchived {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewTransaction = true
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {  // not .secondaryAction: iOS nests that in its own "…" overflow menu
            Menu {
                if wallet.isArchived {
                    Button("Restore Wallet", systemImage: "arrow.uturn.backward", action: restore)
                } else {
                    Button("Edit Wallet", systemImage: "pencil") { showingEdit = true }
                    if wallet.hasHistory {
                        Button("Archive Wallet", systemImage: "archivebox") { confirmingArchive = true }
                    }
                }
                if !wallet.hasHistory {
                    Button("Delete Wallet", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private func archive() {
        do { try app.wallets.archive(wallet) } catch { self.error = AlertError(error) }
    }

    private func restore() {
        do { try app.wallets.restore(wallet) } catch { self.error = AlertError(error) }
    }

    private func delete() {
        do {
            try app.wallets.delete(wallet)
            dismiss()
        } catch {
            self.error = AlertError(error, title: String(localized: "Couldn't Delete", bundle: .l10n))
        }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query(sort: \Wallet.sortOrder) var wallets: [Wallet]
    NavigationStack {
        if let wallet = wallets.first {
            WalletDetailView(wallet: wallet)
                .financeDestinations()
        }
    }
}
