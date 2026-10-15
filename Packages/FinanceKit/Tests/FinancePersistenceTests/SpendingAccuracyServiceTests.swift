import Foundation
import SwiftData
import Testing
import FinanceDomain
@testable import FinancePersistence

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }
private func usd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .usd) }

private var monthStart: Date {
    PreviewFixtures.calendarPolicy.calendar.dateInterval(of: .month, for: Ledger.clock)!.start
}

// MARK: - Irregular expenses

@Suite("Irregular expenses")
struct IrregularExpenseTests {
    @Test func categoryDefaultAppliesAndTheTransactionCanOverride() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 20_000_000)
        let travel = try ledger.category("expense.travel")
        try ledger.categories.update(travel, with: CategoryDraft(
            name: travel.name, type: .expense, iconName: travel.iconName,
            colorIdentifier: travel.colorIdentifier, isIrregular: true))

        let flight = try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(5_000_000), wallet: cash, category: travel, date: Ledger.clock))
        let snack = try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(50_000), wallet: cash, category: travel, date: Ledger.clock,
            isIrregular: false))
        let laptop = try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(10_000_000), wallet: cash, category: try ledger.category("expense.shopping"),
            date: Ledger.clock, isIrregular: true))
        let salary = try ledger.transactions.create(CashFlowDraft(
            kind: .income, amount: vnd(1), wallet: cash, category: try ledger.category("income.salary"),
            date: Ledger.clock, isIrregular: true))

        #expect(flight.isIrregular)                  // category default
        #expect(!snack.isIrregular)                  // overridden
        #expect(laptop.isIrregular)                  // overridden the other way
        #expect(!salary.isIrregular)                 // only expenses can be irregular

        // Changing the category's default never rewrites existing expenses.
        try ledger.categories.update(travel, with: CategoryDraft(
            name: travel.name, type: .expense, iconName: travel.iconName, colorIdentifier: travel.colorIdentifier))
        #expect(flight.isIrregular)
    }

    @Test func cashFlowAndBalancesAgree() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 20_000_000)
        try ledger.record(.expense, 300_000, in: cash)
        try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(8_000_000), wallet: cash, category: try ledger.category("expense.travel"),
            date: Ledger.clock, isIrregular: true))

        let snapshot = try ReportService(context: ledger.context).snapshot()
        let range = PreviewFixtures.calendarPolicy.dayRange(for: try DateRange(
            start: monthStart, end: PreviewFixtures.calendarPolicy.calendar.date(byAdding: .month, value: 1, to: monthStart)!))
        let flow = try ReportRules.cashFlow(snapshot, in: range, currency: .vnd)
        #expect(flow.expenses == vnd(300_000))
        #expect(flow.irregularExpenses == vnd(8_000_000))
        #expect(flow.net == vnd(-8_300_000))
        #expect(try cash.currentBalance() == vnd(11_700_000))
    }

    @Test func budgetsIgnoreIrregularExpenses() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 20_000_000)
        let food = try ledger.category("expense.food")
        let budget = try ledger.budgets.create(BudgetDraft(
            name: "Food", plannedAmount: vnd(4_000_000), period: .monthly, startDate: monthStart, categories: [food]))
        try ledger.record(.expense, 100_000, in: cash)
        try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(3_000_000), wallet: cash, category: food, date: Ledger.clock,
            note: "Wedding banquet", isIrregular: true))

        #expect(try ledger.budgets.progress(for: budget, at: Ledger.clock).spent == vnd(100_000))
    }
}

// MARK: - Sub-categories

@Suite("Sub-categories")
struct SubcategoryTests {
    private func coffee(_ ledger: Ledger, parent: LedgerCategory?) throws -> LedgerCategory {
        try ledger.categories.create(CategoryDraft(
            name: "Coffee", type: .expense, iconName: "cup.and.saucer", colorIdentifier: "brown", parent: parent))
    }

    @Test func parentMustBeTopLevelOfTheSameType() throws {
        let ledger = try Ledger()
        let food = try ledger.category("expense.food")
        let coffee = try coffee(ledger, parent: food)
        #expect(coffee.parent?.id == food.id)
        #expect(coffee.path == "\(food.name) / Coffee")

        // Two levels at most.
        #expect(throws: LedgerValidationError.invalidParentCategory) {
            try ledger.categories.create(CategoryDraft(
                name: "Espresso", type: .expense, iconName: "cup.and.saucer", colorIdentifier: "brown", parent: coffee))
        }
        // Same type.
        #expect(throws: LedgerValidationError.invalidParentCategory) {
            try ledger.categories.create(CategoryDraft(
                name: "Bonus", type: .income, iconName: "gift", colorIdentifier: "green", parent: food))
        }
        // Never itself.
        #expect(throws: LedgerValidationError.invalidParentCategory) {
            try ledger.categories.update(food, with: CategoryDraft(
                name: food.name, type: .expense, iconName: food.iconName, colorIdentifier: food.colorIdentifier, parent: food))
        }
        // A category with sub-categories stays top-level.
        #expect(throws: LedgerValidationError.categoryHasSubcategories) {
            try ledger.categories.update(food, with: CategoryDraft(
                name: food.name, type: .expense, iconName: food.iconName, colorIdentifier: food.colorIdentifier,
                parent: try ledger.category("expense.shopping")))
        }
        #expect(food.parent == nil)
    }

    @Test func typeIsLockedWhileUsedByChildrenBudgetsOrRecurringItems() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet()
        let parent = try ledger.categories.create(CategoryDraft(
            name: "Pets", type: .expense, iconName: "pawprint", colorIdentifier: "brown"))
        let child = try coffee(ledger, parent: parent)
        #expect(throws: LedgerValidationError.categoryTypeInUse) {
            try ledger.categories.update(parent, with: CategoryDraft(
                name: "Pets", type: .income, iconName: "pawprint", colorIdentifier: "brown"))
        }

        try ledger.categories.update(child, with: CategoryDraft(
            name: "Coffee", type: .expense, iconName: "cup.and.saucer", colorIdentifier: "brown"))   // moved to top level
        try ledger.budgets.create(BudgetDraft(
            name: "Pets", plannedAmount: vnd(1_000_000), period: .monthly, startDate: monthStart, categories: [parent]))
        #expect(throws: LedgerValidationError.categoryTypeInUse) {
            try ledger.categories.update(parent, with: CategoryDraft(
                name: "Pets", type: .income, iconName: "pawprint", colorIdentifier: "brown"))
        }

        let unused = try ledger.categories.create(CategoryDraft(
            name: "Gym", type: .expense, iconName: "dumbbell", colorIdentifier: "red"))
        try ledger.recurring.create(RecurringDraft(
            name: "Gym", kind: .expense, amount: vnd(500_000), wallet: cash, category: unused,
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: Ledger.clock)))
        #expect(throws: LedgerValidationError.categoryTypeInUse) {
            try ledger.categories.update(unused, with: CategoryDraft(
                name: "Gym", type: .income, iconName: "dumbbell", colorIdentifier: "red"))
        }
    }

    @Test func hierarchyListsChildrenUnderTheirParent() throws {
        let ledger = try Ledger()
        let food = try ledger.category("expense.food")
        let coffee = try coffee(ledger, parent: food)
        let all = try ledger.context.fetch(FetchDescriptor<LedgerCategory>(sortBy: [SortDescriptor(\.sortOrder)]))

        let hierarchy = all.inHierarchy()
        #expect(hierarchy.count == all.count)
        let foodIndex = try #require(hierarchy.firstIndex { $0.category.id == food.id })
        #expect(hierarchy[foodIndex + 1].category.id == coffee.id)
        #expect(hierarchy[foodIndex + 1].level == 1)
        #expect(hierarchy[foodIndex].level == 0)

        // Without its parent in the list, a child is shown at the top level.
        #expect([coffee].inHierarchy().map(\.level) == [0])
    }

    @Test func reportsRollChildrenIntoTheParent() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 1_000_000)
        let food = try ledger.category("expense.food")
        let coffee = try coffee(ledger, parent: food)
        try ledger.record(.expense, 100_000, in: cash)
        try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(45_000), wallet: cash, category: coffee, date: Ledger.clock))

        let snapshot = try ReportService(context: ledger.context).snapshot()
        let range = PreviewFixtures.calendarPolicy.dayRange(for: try DateRange(
            start: monthStart, end: PreviewFixtures.calendarPolicy.calendar.date(byAdding: .month, value: 1, to: monthStart)!))
        let shares = try ReportRules.expensesByCategory(snapshot, in: range, currency: .vnd)
        #expect(shares.map(\.key) == [.category(food.id)])
        #expect(shares.first?.amount == vnd(145_000))
        let within = try ReportRules.expensesWithin(food.id, snapshot, in: range, currency: .vnd)
        #expect(within.map(\.amount) == [vnd(100_000), vnd(45_000)])
    }
}

// MARK: - Budget alerts

@Suite("Budget alert thresholds")
struct BudgetAlertThresholdTests {
    @Test func thresholdsAreSavedSortedAndCanBeTurnedOff() throws {
        let ledger = try Ledger()
        let food = try ledger.category("expense.food")
        let budget = try ledger.budgets.create(BudgetDraft(
            name: "Food", plannedAmount: vnd(4_000_000), period: .monthly, startDate: monthStart,
            categories: [food], alertThresholds: [100, 50, 90]))
        #expect(budget.alertThresholdPercents == [50, 90, 100])

        try ledger.budgets.update(budget, with: BudgetDraft(
            name: "Food", plannedAmount: vnd(4_000_000), period: .monthly, startDate: monthStart,
            categories: [food], alertThresholds: []))
        #expect(budget.alertThresholdPercents.isEmpty)

        #expect(throws: LedgerValidationError.invalidAlertThresholds) {
            try ledger.budgets.update(budget, with: BudgetDraft(
                name: "Food", plannedAmount: vnd(4_000_000), period: .monthly, startDate: monthStart,
                categories: [food], alertThresholds: [75]))
        }
        #expect(budget.alertThresholdPercents.isEmpty)
    }

    @Test func customThresholdsDriveAlerts() throws {
        let ledger = try Ledger()
        let cash = try ledger.makeWallet(opening: 10_000_000)
        let budget = try ledger.budgets.create(BudgetDraft(
            name: "Food", plannedAmount: vnd(1_000_000), period: .monthly, startDate: monthStart,
            categories: [try ledger.category("expense.food")], alertThresholds: [50, 90]))
        try ledger.record(.expense, 600_000, in: cash)

        let progress = try ledger.budgets.progress(for: budget, at: Ledger.clock)
        #expect(BudgetAlertRules.newlyReachedThresholds(
            progress: progress, thresholds: budget.alertThresholdPercents, alreadyAlerted: []) == [50])
        #expect(BudgetAlertRules.newlyReachedThresholds(
            progress: progress, thresholds: [], alreadyAlerted: []).isEmpty)
    }
}

// MARK: - Recurring transfers

@Suite("Recurring transfers")
struct RecurringTransferTests {
    /// Monthly 2,000,000 from Bank to Savings, starting 1 October (the clock is 12 October).
    @discardableResult
    private func saving(_ ledger: Ledger, from bank: Wallet, to savings: Wallet,
                        amount: Money = vnd(2_000_000), received: Money? = nil) throws -> RecurringTransaction {
        try ledger.recurring.create(RecurringDraft(
            name: "Save", kind: .transfer, amount: amount, wallet: bank, category: nil,
            destination: savings, receivedAmount: received,
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: monthStart)))
    }

    @Test func recordingMovesMoneyOnceAndIsNotSpending() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 10_000_000)
        let savings = try ledger.makeWallet("Savings", type: .bankAccount)
        let definition = try saving(ledger, from: bank, to: savings)
        #expect(definition.categoryID == nil)
        #expect(definition.destinationWalletID == savings.id)
        #expect(definition.receivedAmountMinorUnits == nil)

        let due = try #require(try ledger.recurring.dueOccurrences(at: Ledger.clock).first)
        let transfer = try ledger.recurring.record(due)
        #expect(transfer.kind == .transfer)
        #expect(transfer.recurringOccurrenceKey == due.key)
        #expect(try bank.currentBalance() == vnd(8_000_000))
        #expect(try savings.currentBalance() == vnd(2_000_000))
        #expect(throws: LedgerValidationError.duplicateOccurrence) { try ledger.recurring.record(due) }
        #expect(try ledger.recurring.recordedTransactions(of: definition).count == 1)
    }

    @Test func crossCurrencyTransfersNeedTheReceivedAmount() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 100_000_000)
        let dollars = try ledger.makeWallet("USD", type: .bankAccount, currency: .usd)

        #expect(throws: LedgerValidationError.missingReceivedAmount) {
            try saving(ledger, from: bank, to: dollars, amount: vnd(26_000_000))
        }
        let definition = try saving(ledger, from: bank, to: dollars, amount: vnd(26_000_000), received: usd(100_000))
        #expect(definition.receivedAmountMinorUnits == 100_000)

        let due = try #require(try ledger.recurring.dueOccurrences(at: Ledger.clock).first)
        // A different amount sent can't silently reuse the stored received amount.
        #expect(throws: LedgerValidationError.missingReceivedAmount) {
            try ledger.recurring.record(due, amount: vnd(25_000_000))
        }
        #expect(try ledger.count(LedgerTransaction.self) == 0)

        try ledger.recurring.record(due, amount: vnd(25_000_000), received: usd(95_000))
        #expect(try dollars.currentBalance() == usd(95_000))
        #expect(try bank.currentBalance() == vnd(75_000_000))
    }

    @Test func invalidTransfersAreRejected() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount)
        #expect(throws: LedgerValidationError.missingDestinationWallet) {
            try ledger.recurring.create(RecurringDraft(
                name: "Save", kind: .transfer, amount: vnd(1), wallet: bank, category: nil,
                schedule: RecurrenceSchedule(frequency: .monthly, startDate: Ledger.clock)))
        }
        #expect(throws: LedgerValidationError.self) {
            try saving(ledger, from: bank, to: bank)
        }
        #expect(throws: LedgerValidationError.missingCategory) {
            try ledger.recurring.create(RecurringDraft(
                name: "Rent", kind: .expense, amount: vnd(1), wallet: bank, category: nil,
                schedule: RecurrenceSchedule(frequency: .monthly, startDate: Ledger.clock)))
        }
        #expect(try ledger.count(RecurringTransaction.self) == 0)
    }

    @Test func destinationWalletCannotBeDeleted() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount)
        let savings = try ledger.makeWallet("Savings", type: .bankAccount)
        try saving(ledger, from: bank, to: savings)
        #expect(throws: LedgerValidationError.walletUsedByRecurring) { try ledger.wallets.delete(savings) }
    }
}

// MARK: - Recurring schedule edits

@Suite("Recurring schedule edits")
struct RecurringScheduleEditTests {
    @Test func movingTheStartBackDoesNotOfferPastOccurrences() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 50_000_000)
        let housing = try ledger.category("expense.housing")
        let calendar = PreviewFixtures.calendarPolicy.calendar
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let rent = try ledger.recurring.create(RecurringDraft(
            name: "Rent", kind: .expense, amount: vnd(6_000_000), wallet: bank, category: housing,
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: nextMonth)))
        #expect(try ledger.recurring.dueOccurrences(at: Ledger.clock).isEmpty)

        // Now weekly from three months ago: none of those weeks were ever due.
        let earlier = calendar.date(byAdding: .month, value: -3, to: monthStart)!
        try ledger.recurring.update(rent, with: RecurringDraft(
            name: "Rent", kind: .expense, amount: vnd(6_000_000), wallet: bank, category: housing,
            schedule: RecurrenceSchedule(frequency: .weekly, startDate: earlier)))
        #expect(try ledger.recurring.dueOccurrences(at: Ledger.clock).allSatisfy {
            $0.occurrence.day >= PreviewFixtures.calendarPolicy.dayKey(for: Ledger.clock)
        })
    }

    @Test func upcomingSkipsOccurrencesHandledEarly() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank")
        let calendar = PreviewFixtures.calendarPolicy.calendar
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let rent = try ledger.recurring.create(RecurringDraft(
            name: "Rent", kind: .expense, amount: vnd(6_000_000), wallet: bank,
            category: try ledger.category("expense.housing"),
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: nextMonth)))
        let next = try #require(try ledger.recurring.upcoming(from: Ledger.clock, days: 60).first)
        rent.handledOccurrenceKeys.append(RecurrenceRules.occurrenceKey(recurringID: rent.id, day: next.occurrence.day))
        try ledger.context.saveOrRollback()

        let after = try #require(try ledger.recurring.upcoming(from: Ledger.clock, days: 60).first)
        #expect(after.occurrence.day > next.occurrence.day)
    }
}

// MARK: - Backup format 2

@MainActor
@Suite("Backup format 2")
struct BackupFormatTwoTests {
    private func service(_ context: ModelContext) -> BackupService {
        BackupService(context: context, now: { Ledger.clock })
    }

    /// Irregular category and expense, a sub-category, custom alert levels and
    /// a cross-currency recurring transfer.
    private func populated() throws -> Ledger {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 100_000_000)
        let dollars = try ledger.makeWallet("USD", type: .bankAccount, currency: .usd)
        let travel = try ledger.category("expense.travel")
        try ledger.categories.update(travel, with: CategoryDraft(
            name: travel.name, type: .expense, iconName: travel.iconName,
            colorIdentifier: travel.colorIdentifier, isIrregular: true))
        let food = try ledger.category("expense.food")
        try ledger.categories.create(CategoryDraft(
            name: "Coffee", type: .expense, iconName: "cup.and.saucer", colorIdentifier: "brown", parent: food))
        try ledger.transactions.create(CashFlowDraft(
            kind: .expense, amount: vnd(8_000_000), wallet: bank, category: travel, date: Ledger.clock))
        try ledger.budgets.create(BudgetDraft(
            name: "Food", plannedAmount: vnd(4_000_000), period: .monthly, startDate: monthStart,
            categories: [food], alertThresholds: [50, 90]))
        try ledger.recurring.create(RecurringDraft(
            name: "Dollars", kind: .transfer, amount: vnd(26_000_000), wallet: bank, category: nil,
            destination: dollars, receivedAmount: usd(100_000),
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: monthStart)))
        return ledger
    }

    @Test func roundTripKeepsTheNewFields() throws {
        let source = try populated()
        let document = try service(source.context).makeBackup()
        #expect(document.formatVersion == 2)
        #expect(document.categories.contains { $0.seedKey == "expense.travel" && $0.isIrregular == true })
        #expect(document.transactions.contains { $0.isIrregular == true })
        let transfer = try #require(document.recurring.first)
        #expect(transfer.kind == "transfer" && transfer.categoryID == nil)
        #expect(transfer.receivedAmountMinorUnits == 100_000)

        let target = try Ledger()
        try service(target.context).restore(try BackupCodec.decode(try BackupCodec.encode(document)))

        let travel = try target.category("expense.travel")
        #expect(travel.isIrregular)
        #expect(try target.context.fetch(FetchDescriptor<LedgerTransaction>()).allSatisfy(\.isIrregular))
        #expect(try target.context.fetch(FetchDescriptor<LedgerCategory>()).contains { $0.name == "Coffee" && $0.parent?.seedKey == "expense.food" })
        #expect(try target.context.fetch(FetchDescriptor<Budget>()).first?.alertThresholdPercents == [50, 90])
        let restored = try #require(try target.context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(restored.kind == .transfer)
        #expect(restored.destinationWalletID == transfer.destinationWalletID)
        #expect(restored.receivedAmountMinorUnits == 100_000)

        // Recording works after the restore.
        let due = try #require(try target.recurring.dueOccurrences(at: Ledger.clock).first)
        try target.recurring.record(due)
    }

    @Test func formatOneFilesStillRestore() throws {
        // A version 1 file: none of the format 2 keys, formatVersion 1.
        let document = try service(try populated().context).makeBackup()
        var json = try #require(try JSONSerialization.jsonObject(with: try BackupCodec.encode(document)) as? [String: Any])
        json["formatVersion"] = 1
        func strip(_ key: String, _ keys: [String]) {
            guard let records = json[key] as? [[String: Any]] else { return }
            json[key] = records.map { record in record.filter { !keys.contains($0.key) } }
        }
        strip("categories", ["isIrregular"])
        strip("transactions", ["isIrregular"])
        json["recurring"] = [] as [Any]          // version 1 had no recurring transfers
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try BackupCodec.decode(data)
        #expect(decoded.formatVersion == 1)
        #expect(decoded.categories.allSatisfy { $0.isIrregular == nil })

        let target = try Ledger()
        try service(target.context).restore(decoded)
        #expect(try target.context.fetch(FetchDescriptor<LedgerTransaction>()).allSatisfy { !$0.isIrregular })
        #expect(try !target.category("expense.travel").isIrregular)
    }

    @Test func validatorChecksTransfersAndThresholds() throws {
        let original = try service(try populated().context).makeBackup()

        var noDestination = original
        noDestination.recurring[0].destinationWalletID = nil
        #expect(throws: BackupError.self) { try BackupValidator.validate(noDestination) }

        var expenseWithoutCategory = original
        expenseWithoutCategory.recurring[0].kind = "expense"
        #expect(throws: BackupError.self) { try BackupValidator.validate(expenseWithoutCategory) }

        var oddThreshold = original
        oddThreshold.budgets[0].alertThresholdPercents = [75]
        #expect(throws: BackupError.self) { try BackupValidator.validate(oddThreshold) }

        #expect(try BackupValidator.validate(original).recurring == 1)
    }
}

// MARK: - I7: wallet currency

@Suite("Wallet currency lock")
struct WalletCurrencyLockTests {
    private func usdDraft(for wallet: Wallet) -> WalletDraft {
        WalletDraft(name: wallet.name, type: .cash, currency: .usd, enteredOpeningBalance: .zero(.usd),
                    iconName: wallet.iconName, colorIdentifier: wallet.colorIdentifier)
    }

    @Test func currencyChangesOnlyWhileNothingReliesOnIt() throws {
        let ledger = try Ledger()
        let free = try ledger.makeWallet("Spare")
        try ledger.wallets.update(free, with: usdDraft(for: free))
        #expect(free.currencyCode == "USD")
    }

    @Test func recurringItemsBudgetsAndGoalsLockTheCurrency() throws {
        let ledger = try Ledger()
        let source = try ledger.makeWallet("Source")
        let target = try ledger.makeWallet("Target")
        try ledger.recurring.create(RecurringDraft(
            name: "Save", kind: .transfer, amount: vnd(1_000), wallet: source, category: nil,
            destination: target, schedule: RecurrenceSchedule(frequency: .monthly, startDate: Ledger.clock)))
        for wallet in [source, target] {           // either side of a recurring transfer
            #expect(throws: LedgerValidationError.walletCurrencyInUse) {
                try ledger.wallets.update(wallet, with: usdDraft(for: wallet))
            }
            #expect(wallet.currencyCode == "VND")
        }

        let budgeted = try ledger.makeWallet("Budgeted")
        try ledger.budgets.create(BudgetDraft(
            name: "Food", plannedAmount: vnd(1_000_000), period: .monthly, startDate: monthStart,
            categories: [try ledger.category("expense.food")], wallets: [budgeted]))
        #expect(throws: LedgerValidationError.walletCurrencyInUse) {
            try ledger.wallets.update(budgeted, with: usdDraft(for: budgeted))
        }

        let linked = try ledger.makeWallet("Linked")
        try ledger.savings.create(SavingsGoalDraft(
            name: "Trip", target: vnd(10_000_000), linkedWallet: linked, iconName: "airplane", colorIdentifier: "teal"))
        #expect(throws: LedgerValidationError.walletCurrencyInUse) {
            try ledger.wallets.update(linked, with: usdDraft(for: linked))
        }
    }
}
