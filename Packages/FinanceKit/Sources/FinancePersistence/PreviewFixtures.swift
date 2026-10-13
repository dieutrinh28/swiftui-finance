import Foundation
import SwiftData
import FinanceDomain

/// Deterministic sample data for SwiftUI previews and automated tests.
///
/// Never called from production code paths: the app only ever shows data
/// the user entered.
public enum PreviewFixtures {
    /// Monday 12 October 2026, 09:00 in Vietnam.
    public static let referenceDate = Date(timeIntervalSince1970: 1_791_770_400)

    public static let calendarPolicy = CalendarPolicy(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)

    public enum WalletName {
        public static let cash = "Cash"
        public static let bank = "Vietcombank"
        public static let creditCard = "Visa Platinum"
        public static let usdSavings = "USD Savings"
    }

    /// Seeds default categories, four wallets, four transactions
    /// (expense, card expense, income, transfer), a monthly food budget, a
    /// savings goal with one contribution and a monthly rent definition, then saves.
    public static func populate(_ context: ModelContext) throws {
        try DefaultCategorySeeder.seedIfNeeded(in: context, now: referenceDate)

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        func category(_ key: String) -> LedgerCategory? {
            categories.first { $0.seedKey == key }
        }

        let cash = Wallet(
            name: WalletName.cash, type: .cash, currency: .vnd,
            openingBalanceMinorUnits: 1_500_000, iconName: "banknote", colorIdentifier: "green",
            sortOrder: 0, createdAt: referenceDate
        )
        let bank = Wallet(
            name: WalletName.bank, type: .bankAccount, currency: .vnd,
            openingBalanceMinorUnits: 18_000_000, iconName: "building.columns", colorIdentifier: "blue",
            sortOrder: 1, createdAt: referenceDate
        )
        let card = Wallet(
            name: WalletName.creditCard, type: .creditCard, currency: .vnd,
            openingBalanceMinorUnits: -2_350_000, iconName: "creditcard", colorIdentifier: "orange",
            sortOrder: 2, createdAt: referenceDate
        )
        let savings = Wallet(
            name: WalletName.usdSavings, type: .savingsAccount, currency: .usd,
            openingBalanceMinorUnits: 120_000, iconName: "archivebox", colorIdentifier: "teal",
            sortOrder: 3, createdAt: referenceDate
        )
        [cash, bank, card, savings].forEach { context.insert($0) }

        let day: TimeInterval = 86_400
        record(.expense, in: context, date: referenceDate.addingTimeInterval(-1 * day + 3 * 3_600),
               category: category("expense.food"), note: "Lunch", legs: [(cash, -65_000)])
        record(.expense, in: context, date: referenceDate.addingTimeInterval(-1 * day + 9 * 3_600),
               category: category("expense.transportation"), note: "Ride home", legs: [(card, -48_000)])
        record(.transfer, in: context, date: referenceDate.addingTimeInterval(-2 * day),
               category: nil, note: "ATM withdrawal", legs: [(bank, -2_000_000), (cash, 2_000_000)])
        record(.income, in: context, date: referenceDate.addingTimeInterval(-3 * day),
               category: category("income.salary"), note: "October salary", legs: [(bank, 25_000_000)])

        // Monthly food budget starting on the first day of the reference month.
        if let food = category("expense.food"),
           let monthStart = calendarPolicy.calendar.dateInterval(of: .month, for: referenceDate)?.start {
            context.insert(Budget(
                name: "Food",
                planned: Money(minorUnits: 4_000_000, currency: .vnd),
                period: .monthly,
                startDate: monthStart,
                categoryIDs: [food.id],
                createdAt: referenceDate
            ))
        }

        // A savings goal (earmark) and a monthly rent definition.
        let goal = SavingsGoal(
            name: "Emergency fund",
            target: Money(minorUnits: 30_000_000, currency: .vnd),
            targetDate: calendarPolicy.calendar.date(byAdding: .month, value: 6, to: referenceDate),
            linkedWalletID: bank.id,
            iconName: "cross.case",
            colorIdentifier: "teal",
            createdAt: referenceDate
        )
        context.insert(goal)
        let contribution = SavingsContribution(
            amountMinorUnits: 5_000_000,
            date: referenceDate.addingTimeInterval(-3 * day),
            dayKey: calendarPolicy.dayKey(for: referenceDate.addingTimeInterval(-3 * day)),
            createdAt: referenceDate
        )
        context.insert(contribution)
        contribution.goal = goal

        if let housing = category("expense.housing"),
           let rentStart = calendarPolicy.calendar.date(byAdding: .month, value: -1,
                                                        to: calendarPolicy.calendar.dateInterval(of: .month, for: referenceDate)!.start) {
            context.insert(RecurringTransaction(
                name: "Rent",
                kind: .expense,
                amount: Money(minorUnits: 6_000_000, currency: .vnd),
                walletID: bank.id,
                categoryID: housing.id,
                schedule: RecurrenceSchedule(frequency: .monthly, startDate: rentStart),
                reminderEnabled: true,
                createdAt: referenceDate
            ))
        }

        try context.saveOrRollback()
    }

    @discardableResult
    private static func record(
        _ kind: TransactionKind,
        in context: ModelContext,
        date: Date,
        category: LedgerCategory?,
        note: String?,
        legs: [(Wallet, Int64)]
    ) -> LedgerTransaction {
        let transaction = LedgerTransaction(
            kind: kind,
            date: date,
            dayKey: calendarPolicy.dayKey(for: date),
            note: note,
            createdAt: date
        )
        context.insert(transaction)
        transaction.category = category

        for (wallet, amount) in legs {
            let entry = LedgerEntry(amountMinorUnits: amount, currencyCode: wallet.currencyCode)
            context.insert(entry)
            entry.wallet = wallet
            entry.transaction = transaction
        }
        return transaction
    }
}
