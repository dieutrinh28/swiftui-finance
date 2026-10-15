import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Wallets tab: active wallets grouped into assets and liabilities, plus archived ones.
struct WalletListView: View {
    @Query(filter: #Predicate<Wallet> { $0.archivedAt == nil }, sort: \Wallet.sortOrder)
    private var wallets: [Wallet]

    @Query(filter: #Predicate<Wallet> { $0.archivedAt != nil }, sort: \Wallet.sortOrder)
    private var archivedWallets: [Wallet]

    @Environment(AppContainer.self) private var app
    @State private var showingNewWallet = false

    var body: some View {
        NavigationStack(path: app.router.binding(for: .wallets)) {
            Group {
                if wallets.isEmpty && archivedWallets.isEmpty {
                    EmptyStateView(
                        systemImage: "wallet.pass",
                        title: "No wallets yet",
                        message: "Wallets hold your cash, bank accounts, e-wallets and cards. You can add as many as you need."
                    ) {
                        Button("Add Wallet", systemImage: "plus") { showingNewWallet = true }
                            .buttonStyle(.appPrimary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        section(for: .asset, title: "Assets", systemImage: "banknote",
                                footer: nil)
                        section(for: .liability, title: "Liabilities", systemImage: "creditcard",
                                footer: "A balance below zero is money you owe. It is never counted as available cash.")
                        if !archivedWallets.isEmpty {
                            Section {
                                ForEach(archivedWallets) { wallet in
                                    NavigationLink(value: wallet) {
                                        WalletRow(wallet: wallet)
                                    }
                                }
                            } header: {
                                Label("Archived", systemImage: "archivebox")
                            } footer: {
                                Text("Archived wallets keep their history and still count in net worth while they hold money.")
                            }
                            .surfaceRows()
                        }
                    }
                    .appGroupedStyle()
                }
            }
            .screenBackground()
            .navigationTitle("Wallets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewWallet = true
                    } label: {
                        Label("Add Wallet", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewWallet) {
                WalletFormView(mode: .create)
            }
            .financeDestinations()
        }
    }

    @ViewBuilder
    private func section(
        for accountClass: AccountClass,
        title: LocalizedStringKey,
        systemImage: String,
        footer: LocalizedStringKey?
    ) -> some View {
        let matching = wallets.filter { $0.type.accountClass == accountClass }
        if !matching.isEmpty {
            Section {
                ForEach(matching) { wallet in
                    NavigationLink(value: wallet) {
                        WalletRow(wallet: wallet)
                    }
                }
            } header: {
                Label(title, systemImage: systemImage)
            } footer: {
                if let footer {
                    Text(footer)
                }
            }
            .surfaceRows()
        }
    }
}

/// One wallet: icon, name, type and currency, and its current balance from the ledger.
struct WalletRow: View {
    let wallet: Wallet

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(systemName: wallet.iconName, tint: PaletteColor(identifier: wallet.colorIdentifier).color)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(wallet.name)
                    .font(.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(wallet.typeWithCurrency)
                    .font(.meta)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: Spacing.sm)
            WalletBalanceText(wallet: wallet)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A wallet's current balance, or an explicit error. Never shows a made-up zero.
struct WalletBalanceText: View {
    let wallet: Wallet
    var font: Font = .amountRow

    var body: some View {
        switch Result(catching: { try wallet.currentBalance() }) {
        case .success(let balance):
            MoneyText(money: balance, tone: .balance, font: font)
        case .failure:
            ReadFailureLabel("Balance unavailable")
        }
    }
}

#Preview("Wallets", traits: .sampleData) {
    WalletListView()
}

#Preview("Empty", traits: .emptyStore) {
    WalletListView()
}
