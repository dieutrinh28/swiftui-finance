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
                    ContentUnavailableView {
                        Label("No wallets yet", systemImage: "wallet.pass")
                    } description: {
                        Text("Wallets hold your cash, bank accounts, e-wallets and cards. You can add as many as you need.")
                    } actions: {
                        Button("Add Wallet") { showingNewWallet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        section(for: .asset, title: "Assets")
                        section(for: .liability, title: "Liabilities")
                        if !archivedWallets.isEmpty {
                            Section("Archived") {
                                ForEach(archivedWallets) { wallet in
                                    NavigationLink(value: wallet) {
                                        WalletRow(wallet: wallet)
                                    }
                                }
                            }
                        }
                    }
                }
            }
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
    private func section(for accountClass: AccountClass, title: LocalizedStringKey) -> some View {
        let matching = wallets.filter { $0.type.accountClass == accountClass }
        if !matching.isEmpty {
            Section(title) {
                ForEach(matching) { wallet in
                    NavigationLink(value: wallet) {
                        WalletRow(wallet: wallet)
                    }
                }
            }
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
                    .font(.body.weight(.medium))
                Text(wallet.typeWithCurrency)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.sm)
            WalletBalanceText(wallet: wallet)
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
            Label("Balance unavailable", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(AppColor.expense)
        }
    }
}

#Preview("Wallets", traits: .sampleData) {
    WalletListView()
}

#Preview("Empty", traits: .emptyStore) {
    WalletListView()
}
