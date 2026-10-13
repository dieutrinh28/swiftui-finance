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
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(transaction.kind?.displayName ?? String(localized: "Unknown"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let amount = transaction.displayAmount, let kind = transaction.kind {
                        MoneyText(money: amount, tone: kind.tone, font: .amountHero)
                    } else {
                        Text("This record is incomplete and can't be shown.")
                            .foregroundStyle(AppColor.expense)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            if transaction.kind == .transfer {
                transferSection
            }

            Section {
                if let category = transaction.category {
                    NavigationLink(value: category) {
                        LabeledContent("Category") {
                            Label(category.name, systemImage: category.iconName)
                        }
                    }
                }
                if transaction.kind != .transfer, let wallet = transaction.primaryWallet {
                    NavigationLink(value: wallet) {
                        LabeledContent("Wallet", value: wallet.name)
                    }
                }
                LabeledContent("Date", value: transaction.date.formatted(date: .long, time: .shortened))
                if let merchant = transaction.merchant {
                    LabeledContent("Merchant", value: merchant)
                }
                if let note = transaction.note {
                    LabeledContent("Note", value: note)
                }
            }

            Section {
                LabeledContent("Created", value: transaction.createdAt.formatted(date: .abbreviated, time: .shortened))
                if transaction.updatedAt != transaction.createdAt {
                    LabeledContent("Last edited", value: transaction.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if transaction.isEditable {
                Section {
                    Button("Delete Transaction", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            } else {
                Section {
                    Text("This transaction involves an archived wallet. Restore the wallet to edit or delete it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if transaction.isEditable {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            TransactionFormView(mode: .edit(transaction))
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
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
                LabeledContent("Exchange rate", value: "1 \(from) = \(rate.formatted(.number.precision(.fractionLength(0...6)))) \(to)")
            }
            Text("Transfers move money between your wallets. They are not counted as income, expenses or budget spending.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func delete() {
        do {
            try app.transactions.delete(transaction)
            dismiss()
        } catch {
            self.error = AlertError(error, title: String(localized: "Couldn't Delete"))
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
