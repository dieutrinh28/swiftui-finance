import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// In-memory store with default categories, two VND wallets and one USD wallet.
@MainActor
final class FormFixture {
    let container: ModelContainer
    let context: ModelContext
    let transactions: TransactionService
    let budgets: BudgetService
    let recurring: RecurringService
    let savings: SavingsService
    let cash: Wallet
    let bank: Wallet
    let usd: Wallet

    nonisolated static let now = PreviewFixtures.referenceDate
    nonisolated static let parser = AmountInputParser(locale: Locale(identifier: "vi_VN"))

    init() throws {
        container = try ModelContainerFactory.makeContainer(at: .inMemory)
        context = ModelContext(container)
        context.autosaveEnabled = false
        try DefaultCategorySeeder.seedIfNeeded(in: context)

        let clock = { FormFixture.now }
        transactions = TransactionService(context: context, calendar: PreviewFixtures.calendarPolicy, now: clock)
        budgets = BudgetService(context: context, calendar: PreviewFixtures.calendarPolicy, now: clock)
        recurring = RecurringService(context: context, calendar: PreviewFixtures.calendarPolicy, now: clock)
        savings = SavingsService(context: context, calendar: PreviewFixtures.calendarPolicy, now: clock)
        let wallets = WalletService(context: context, now: clock)
        func wallet(_ name: String, _ currency: CurrencyDefinition, _ opening: Int64) throws -> Wallet {
            try wallets.create(WalletDraft(
                name: name, type: .cash, currency: currency,
                enteredOpeningBalance: Money(minorUnits: opening, currency: currency),
                iconName: "banknote", colorIdentifier: "green"
            ))
        }
        cash = try wallet("Cash", .vnd, 1_000_000)
        bank = try wallet("Bank", .vnd, 5_000_000)
        usd = try wallet("USD", .usd, 10_000)
    }

    func category(_ seedKey: String) throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.seedKey == seedKey })
    }

    func model(_ mode: TransactionFormModel.Mode) -> TransactionFormModel {
        TransactionFormModel(mode: mode, service: transactions, now: FormFixture.now, parser: FormFixture.parser)
    }

    func budgetModel(_ mode: BudgetFormModel.Mode) -> BudgetFormModel {
        BudgetFormModel(mode: mode, service: budgets, now: FormFixture.now,
                        calendar: PreviewFixtures.calendarPolicy, parser: FormFixture.parser)
    }

    func recurringModel(_ mode: RecurringFormModel.Mode) -> RecurringFormModel {
        RecurringFormModel(mode: mode, service: recurring, policy: PreviewFixtures.calendarPolicy,
                           now: { FormFixture.now }, parser: FormFixture.parser)
    }

    func savingsModel(_ mode: SavingsGoalFormModel.Mode) -> SavingsGoalFormModel {
        SavingsGoalFormModel(mode: mode, service: savings, policy: PreviewFixtures.calendarPolicy,
                             now: { FormFixture.now }, parser: FormFixture.parser)
    }

    func allCategories() throws -> [LedgerCategory] {
        try context.fetch(FetchDescriptor<LedgerCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    var allWallets: [Wallet] { [cash, bank, usd] }

    func transactionCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<LedgerTransaction>())
    }
}
