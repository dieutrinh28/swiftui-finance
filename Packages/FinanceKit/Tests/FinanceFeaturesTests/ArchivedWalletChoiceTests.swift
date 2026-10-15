import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Invariant I15: archived wallets are never offered where the user picks a wallet.
@MainActor
@Suite("Archived wallets are not offered")
struct ArchivedWalletChoiceTests {
    private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }

    @Test func choicesLeaveOutArchivedWallets() throws {
        let fixture = try FormFixture()
        try fixture.wallets.archive(fixture.bank)

        #expect(WalletChoices.selectable(from: fixture.allWallets).map(\.name) == ["Cash", "USD"])
        #expect(WalletChoices.selectable(from: fixture.allWallets, currencyCode: "VND").map(\.name) == ["Cash"])
        #expect(WalletChoices.selectable(from: fixture.allWallets, excluding: fixture.cash).map(\.name) == ["USD"])

        let transaction = fixture.model(.create(wallet: nil))
        transaction.selectDefaultWalletIfNeeded(from: [fixture.bank, fixture.cash])
        #expect(transaction.wallet?.id == fixture.cash.id)
    }

    @Test func recurringItemOnAnArchivedWalletAsksForAnother() throws {
        let fixture = try FormFixture()
        let rent = try fixture.recurring.create(RecurringDraft(
            name: "Rent", kind: .expense, amount: vnd(6_000_000), wallet: fixture.bank,
            category: try fixture.category("expense.housing"),
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: FormFixture.now)
        ))
        try fixture.wallets.archive(fixture.bank)

        let model = fixture.recurringModel(.edit(rent))
        #expect(model.wallet == nil)
        #expect(model.archivedWalletNames == ["Bank"])
        #expect(!model.walletChoices(from: fixture.allWallets).contains { $0.id == fixture.bank.id })
        model.selectDefaultWalletIfNeeded(from: fixture.allWallets)
        #expect(model.wallet == nil)                     // not picked silently
        #expect(!model.canSave)

        model.wallet = fixture.cash
        #expect(model.canSave)
        #expect(model.save())
        #expect(try fixture.recurring.hold(of: rent) == nil)
    }

    @Test func transferDestinationLeavesOutArchivedWallets() throws {
        let fixture = try FormFixture()
        try fixture.wallets.archive(fixture.bank)
        let model = fixture.recurringModel(.create)
        model.kind = .transfer
        model.wallet = fixture.cash
        #expect(model.destinationChoices(from: fixture.allWallets).map(\.name) == ["USD"])
    }

    @Test func goalKeptInAnArchivedWalletLosesTheLinkWhenSaved() throws {
        let fixture = try FormFixture()
        let goal = try fixture.savings.create(SavingsGoalDraft(
            name: "Trip", target: vnd(10_000_000), linkedWallet: fixture.bank,
            iconName: "airplane", colorIdentifier: "teal"
        ))
        try fixture.wallets.archive(fixture.bank)

        let model = fixture.savingsModel(.edit(goal))
        #expect(model.linkedWallet == nil)
        #expect(model.archivedWalletName == "Bank")
        #expect(model.availableWallets(from: fixture.allWallets).map(\.name) == ["Cash"])
        #expect(model.save())
        #expect(goal.linkedWalletID == nil)

        #expect(throws: LedgerValidationError.archivedWallet) {
            try fixture.savings.update(goal, with: SavingsGoalDraft(
                name: "Trip", target: vnd(10_000_000), linkedWallet: fixture.bank,
                iconName: "airplane", colorIdentifier: "teal"
            ))
        }
    }

    @Test func budgetKeepsAnArchivedWalletButCannotAddOne() throws {
        let fixture = try FormFixture()
        let food = try fixture.category("expense.food")
        let start = PreviewFixtures.calendarPolicy.calendar.dateInterval(of: .month, for: FormFixture.now)!.start
        func draft(_ wallets: [Wallet]) -> BudgetDraft {
            BudgetDraft(name: "Food", plannedAmount: vnd(4_000_000), period: .monthly,
                        startDate: start, categories: [food], wallets: wallets)
        }
        let budget = try fixture.budgets.create(draft([fixture.bank]))
        try fixture.wallets.archive(fixture.bank)

        let model = fixture.budgetModel(.edit(budget))
        #expect(model.selectableWallets(from: fixture.allWallets).map(\.name) == ["Cash"])
        #expect(model.archivedSelectedWallets(from: fixture.allWallets).map(\.name) == ["Bank"])
        #expect(model.save(categories: [food], wallets: fixture.allWallets))
        #expect(budget.walletIDs == [fixture.bank.id])                     // kept, not dropped

        let other = try fixture.budgets.create(draft([fixture.cash]))
        #expect(throws: LedgerValidationError.archivedWallet) {
            try fixture.budgets.update(other, with: draft([fixture.cash, fixture.bank]))
        }
        #expect(throws: LedgerValidationError.archivedWallet) {
            try fixture.budgets.create(draft([fixture.bank]))
        }
    }
}
