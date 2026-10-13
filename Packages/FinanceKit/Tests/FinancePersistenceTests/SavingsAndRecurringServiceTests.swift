import Foundation
import SwiftData
import Testing
import FinanceDomain
import FinancePersistence

private func vnd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: .vnd) }

@Suite("Savings goals")
struct SavingsServiceTests {
    private func goal(_ ledger: Ledger, target: Int64 = 30_000_000, wallet: Wallet? = nil) throws -> SavingsGoal {
        try ledger.savings.create(SavingsGoalDraft(
            name: "Emergency fund", target: vnd(target),
            targetDate: PreviewFixtures.calendarPolicy.calendar.date(byAdding: .month, value: 5, to: Ledger.clock),
            linkedWallet: wallet, iconName: "cross.case", colorIdentifier: "teal"
        ))
    }

    @Test func contributionsAreEarmarksAndNeverChangeBalancesOrNetWorth() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", type: .bankAccount, opening: 20_000_000)
        let fund = try goal(ledger, wallet: bank)
        let reports = ReportService(context: ledger.context)
        let netWorthBefore = try ReportRules.positions(reports.snapshot()).first?.netWorth

        try ledger.savings.addEntry(to: fund, amount: vnd(5_000_000), isWithdrawal: false, date: Ledger.clock)
        try ledger.savings.addEntry(to: fund, amount: vnd(1_000_000), isWithdrawal: true, date: Ledger.clock)

        let progress = try ledger.savings.progress(of: fund, at: Ledger.clock)
        #expect(progress.saved == vnd(4_000_000))
        #expect(progress.remaining == vnd(26_000_000))
        #expect(try bank.currentBalance() == vnd(20_000_000))
        #expect(try ReportRules.positions(reports.snapshot()).first?.netWorth == netWorthBefore)
        #expect(try ledger.count(LedgerTransaction.self) == 0)
    }

    @Test func withdrawalCannotExceedSaved() throws {
        let ledger = try Ledger()
        let fund = try goal(ledger)
        try ledger.savings.addEntry(to: fund, amount: vnd(100_000), isWithdrawal: false, date: Ledger.clock)

        #expect(throws: LedgerValidationError.withdrawalExceedsSavings) {
            try ledger.savings.addEntry(to: fund, amount: vnd(100_001), isWithdrawal: true, date: Ledger.clock)
        }
        #expect(fund.contributionsNewestFirst.count == 1)
    }

    @Test func deletingAContributionCannotLeaveANegativeTotal() throws {
        let ledger = try Ledger()
        let fund = try goal(ledger)
        let deposit = try ledger.savings.addEntry(to: fund, amount: vnd(100_000), isWithdrawal: false, date: Ledger.clock)
        try ledger.savings.addEntry(to: fund, amount: vnd(60_000), isWithdrawal: true, date: Ledger.clock)

        #expect(throws: LedgerValidationError.withdrawalExceedsSavings) {
            try ledger.savings.delete(deposit)
        }
        #expect(try ledger.savings.progress(of: fund, at: Ledger.clock).saved == vnd(40_000))
    }

    @Test func linkedWalletMustShareCurrencyAndAllocationIsChecked() throws {
        let ledger = try Ledger()
        let usd = try ledger.makeWallet("USD", currency: .usd)
        #expect(throws: LedgerValidationError.currencyMismatch(walletCurrency: "USD", amountCurrency: "VND")) {
            try goal(ledger, wallet: usd)
        }

        let bank = try ledger.makeWallet("Bank", opening: 1_000_000)
        let fund = try goal(ledger, wallet: bank)
        try ledger.savings.addEntry(to: fund, amount: vnd(1_500_000), isWithdrawal: false, date: Ledger.clock)
        let allocation = try #require(try ledger.savings.allocation(of: bank))
        #expect(allocation.allocated == vnd(1_500_000))
        #expect(allocation.exceedsBalance)

        #expect(throws: LedgerValidationError.walletUsedBySavingsGoal) {
            try ledger.wallets.delete(bank)
        }
    }

    @Test func deletingAGoalRemovesItsContributionsOnly() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 1_000_000)
        let fund = try goal(ledger)
        try ledger.savings.addEntry(to: fund, amount: vnd(500_000), isWithdrawal: false, date: Ledger.clock)

        try ledger.savings.delete(fund)
        #expect(try ledger.count(SavingsGoal.self) == 0)
        #expect(try ledger.count(SavingsContribution.self) == 0)
        #expect(try bank.currentBalance() == vnd(1_000_000))
    }

    @Test func completeArchiveRestore() throws {
        let ledger = try Ledger()
        let fund = try goal(ledger)
        try ledger.savings.setCompleted(fund, true)
        #expect(fund.isCompleted)
        try ledger.savings.archive(fund)
        #expect(fund.isArchived)
        try ledger.savings.restore(fund)
        #expect(!fund.isArchived)
    }

    @Test func currencyIsLockedOnceThereAreContributions() throws {
        let ledger = try Ledger()
        let fund = try goal(ledger)
        try ledger.savings.addEntry(to: fund, amount: vnd(1), isWithdrawal: false, date: Ledger.clock)
        #expect(throws: LedgerValidationError.goalCurrencyLocked) {
            try ledger.savings.update(fund, with: SavingsGoalDraft(
                name: "Fund", target: Money(minorUnits: 100, currency: .usd), iconName: "star", colorIdentifier: "blue"))
        }
    }
}

@Suite("Recurring transactions")
struct RecurringServiceTests {
    /// Monthly rent of 6,000,000 from the bank, starting 1 September 2026 (the clock is 12 October).
    private func rent(_ ledger: Ledger, bank: Wallet, start: Date? = nil, reminder: Bool = false) throws -> RecurringTransaction {
        let calendar = PreviewFixtures.calendarPolicy.calendar
        let september = calendar.date(byAdding: .month, value: -1, to: calendar.dateInterval(of: .month, for: Ledger.clock)!.start)!
        return try ledger.recurring.create(RecurringDraft(
            name: "Rent", kind: .expense, amount: vnd(6_000_000), wallet: bank,
            category: try ledger.category("expense.housing"),
            schedule: RecurrenceSchedule(frequency: .monthly, startDate: start ?? september),
            reminderEnabled: reminder
        ))
    }

    @Test func pastOccurrencesBecomeDue() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 50_000_000)
        try rent(ledger, bank: bank)

        let due = try ledger.recurring.dueOccurrences(at: Ledger.clock)
        #expect(due.map(\.occurrence.day) == [DayKey(year: 2026, month: 9, day: 1), DayKey(year: 2026, month: 10, day: 1)])
        #expect(try ledger.count(LedgerTransaction.self) == 0)      // nothing is generated automatically
    }

    @Test func recordingCreatesOneTaggedTransactionAndCannotDuplicate() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 50_000_000)
        try rent(ledger, bank: bank)
        let first = try #require(try ledger.recurring.dueOccurrences(at: Ledger.clock).first)

        let transaction = try ledger.recurring.record(first)
        #expect(transaction.recurringOccurrenceKey == first.key)
        #expect(transaction.day == first.occurrence.day)
        #expect(try bank.currentBalance() == vnd(44_000_000))

        #expect(throws: LedgerValidationError.duplicateOccurrence) {
            try ledger.recurring.record(first)
        }
        #expect(try ledger.count(LedgerTransaction.self) == 1)
        #expect(try ledger.recurring.dueOccurrences(at: Ledger.clock).count == 1)
    }

    @Test func ledgerKeyAlsoPreventsDuplicates() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 50_000_000)
        let definition = try rent(ledger, bank: bank)
        let first = try #require(try ledger.recurring.dueOccurrences(at: Ledger.clock).first)
        try ledger.recurring.record(first)

        // Even if the handled list were lost, the occurrence key in the ledger blocks a second copy.
        definition.handledOccurrenceKeys = []
        try ledger.context.saveOrRollback()
        let again = try #require(try ledger.recurring.dueOccurrences(at: Ledger.clock).first { $0.key == first.key })
        #expect(throws: LedgerValidationError.duplicateOccurrence) {
            try ledger.recurring.record(again)
        }
        #expect(try ledger.count(LedgerTransaction.self) == 1)
    }

    @Test func recordWithDifferentAmountAndSkip() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 50_000_000)
        try rent(ledger, bank: bank)
        let due = try ledger.recurring.dueOccurrences(at: Ledger.clock)

        try ledger.recurring.skip(due[0])
        try ledger.recurring.record(due[1], amount: vnd(6_200_000))

        #expect(try ledger.recurring.dueOccurrences(at: Ledger.clock).isEmpty)
        #expect(try bank.currentBalance() == vnd(43_800_000))
    }

    @Test func pausedDefinitionsAreNotDue() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 0)
        let definition = try rent(ledger, bank: bank)
        try ledger.recurring.setPaused(definition, true)
        #expect(try ledger.recurring.dueOccurrences(at: Ledger.clock).isEmpty)
        #expect(try ledger.recurring.plannedReminders(after: Ledger.clock).isEmpty)
    }

    @Test func archivedWalletBlocksRecordingWithoutWriting() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 50_000_000)
        try rent(ledger, bank: bank)
        let first = try #require(try ledger.recurring.dueOccurrences(at: Ledger.clock).first)
        try ledger.wallets.archive(bank)

        #expect(throws: LedgerValidationError.archivedWallet) {
            try ledger.recurring.record(first)
        }
        #expect(try ledger.count(LedgerTransaction.self) == 0)
        #expect(try ledger.recurring.dueOccurrences(at: Ledger.clock).count == 2)
    }

    @Test func upcomingAndReminders() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 0)
        try rent(ledger, bank: bank, reminder: true)

        let upcoming = try ledger.recurring.upcoming(from: Ledger.clock, days: 30)
        #expect(upcoming.map(\.occurrence.day) == [DayKey(year: 2026, month: 11, day: 1)])

        let reminders = try ledger.recurring.plannedReminders(after: Ledger.clock, perDefinition: 2)
        #expect(reminders.count == 2)
        #expect(reminders.first?.title == "Rent")
        #expect(PreviewFixtures.calendarPolicy.dayKey(for: reminders[0].fireDate) == DayKey(year: 2026, month: 11, day: 1))
    }

    @Test func invalidDefinitionsAreRejected() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 0)
        #expect(throws: LedgerValidationError.categoryTypeMismatch(required: .expense, actual: .income)) {
            try ledger.recurring.create(RecurringDraft(
                name: "Rent", kind: .expense, amount: vnd(1), wallet: bank,
                category: try ledger.category("income.salary"),
                schedule: RecurrenceSchedule(frequency: .monthly, startDate: Ledger.clock)))
        }
        #expect(throws: LedgerValidationError.invalidRecurrence) {
            try ledger.recurring.create(RecurringDraft(
                name: "Rent", kind: .expense, amount: vnd(1), wallet: bank,
                category: try ledger.category("expense.housing"),
                schedule: RecurrenceSchedule(frequency: .monthly, interval: 0, startDate: Ledger.clock)))
        }
        #expect(try ledger.count(RecurringTransaction.self) == 0)
    }

    @Test func referencesBlockDeletes() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 0)
        try rent(ledger, bank: bank)
        #expect(throws: LedgerValidationError.walletUsedByRecurring) { try ledger.wallets.delete(bank) }
        #expect(throws: LedgerValidationError.categoryUsedByRecurring) {
            try ledger.categories.delete(try ledger.category("expense.housing"))
        }
    }

    @Test func deletingADefinitionKeepsRecordedTransactions() throws {
        let ledger = try Ledger()
        let bank = try ledger.makeWallet("Bank", opening: 50_000_000)
        let definition = try rent(ledger, bank: bank)
        try ledger.recurring.record(try #require(try ledger.recurring.dueOccurrences(at: Ledger.clock).first))
        #expect(try ledger.recurring.recordedTransactions(of: definition).count == 1)

        try ledger.recurring.delete(definition)
        #expect(try ledger.count(LedgerTransaction.self) == 1)
    }
}
