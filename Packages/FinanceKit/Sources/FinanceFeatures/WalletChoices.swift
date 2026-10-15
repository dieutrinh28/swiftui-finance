import Foundation
import FinancePersistence

/// The one rule for every list where the user picks a wallet (invariant I15):
/// archived wallets are never offered. Their history stays where it is (the
/// wallet's own screen, reports, budgets); restoring the wallet offers it again.
///
/// When a record being edited still points at an archived wallet, its form
/// says so and asks for another wallet (recurring item, goal); a budget keeps
/// counting the archived wallet's past spending without listing it.
public enum WalletChoices {
    /// Active wallets, in the given order, optionally in one currency and
    /// without one wallet (the other side of a transfer).
    public static func selectable(
        from wallets: [Wallet],
        currencyCode: String? = nil,
        excluding excluded: Wallet? = nil
    ) -> [Wallet] {
        wallets.filter { wallet in
            !wallet.isArchived
                && (currencyCode.map { wallet.currencyCode == $0 } ?? true)
                && wallet.id != excluded?.id
        }
    }
}
