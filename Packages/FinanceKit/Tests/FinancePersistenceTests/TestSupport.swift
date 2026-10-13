import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence

/// An isolated store with services, default categories and a fixed clock.
final class Ledger {
    let container: ModelContainer
    let context: ModelContext
    let wallets: WalletService
    let transactions: TransactionService
    let categories: CategoryService
    let budgets: BudgetService
    let savings: SavingsService
    let recurring: RecurringService

    static let clock = PreviewFixtures.referenceDate

    init(location: StoreLocation = .inMemory) throws {
        container = try ModelContainerFactory.makeContainer(at: location)
        context = ModelContext(container)
        context.autosaveEnabled = false
        let now = { Ledger.clock }
        wallets = WalletService(context: context, now: now)
        transactions = TransactionService(context: context, calendar: PreviewFixtures.calendarPolicy, now: now)
        categories = CategoryService(context: context, now: now)
        budgets = BudgetService(context: context, calendar: PreviewFixtures.calendarPolicy, now: now)
        savings = SavingsService(context: context, calendar: PreviewFixtures.calendarPolicy, now: now)
        recurring = RecurringService(context: context, calendar: PreviewFixtures.calendarPolicy, now: now)
        try DefaultCategorySeeder.seedIfNeeded(in: context)
    }

    func category(_ seedKey: String) throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.seedKey == seedKey })
    }

    @discardableResult
    func makeWallet(
        _ name: String = "Cash",
        type: WalletType = .cash,
        currency: CurrencyDefinition = .vnd,
        opening: Int64 = 0
    ) throws -> Wallet {
        try wallets.create(WalletDraft(
            name: name, type: type, currency: currency,
            enteredOpeningBalance: Money(minorUnits: opening, currency: currency),
            iconName: type == .creditCard ? "creditcard" : "banknote", colorIdentifier: "green"
        ))
    }

    @discardableResult
    func record(
        _ kind: TransactionKind,
        _ minor: Int64,
        in wallet: Wallet,
        category seedKey: String? = nil,
        date: Date = Ledger.clock
    ) throws -> LedgerTransaction {
        let key = seedKey ?? (kind == .income ? "income.salary" : "expense.food")
        return try transactions.create(CashFlowDraft(
            kind: kind,
            amount: Money(minorUnits: minor, currency: try #require(wallet.currency)),
            wallet: wallet,
            category: try category(key),
            date: date
        ))
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}
