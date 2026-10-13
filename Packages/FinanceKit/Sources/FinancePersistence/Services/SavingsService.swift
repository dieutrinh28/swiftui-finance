import Foundation
import SwiftData
import FinanceDomain

public struct SavingsGoalDraft {
    public var name: String
    public var target: Money
    public var targetDate: Date?
    /// Where the money is kept (informational). Must use the goal's currency.
    public var linkedWallet: Wallet?
    public var note: String?
    public var iconName: String
    public var colorIdentifier: String

    public init(
        name: String,
        target: Money,
        targetDate: Date? = nil,
        linkedWallet: Wallet? = nil,
        note: String? = nil,
        iconName: String,
        colorIdentifier: String
    ) {
        self.name = name
        self.target = target
        self.targetDate = targetDate
        self.linkedWallet = linkedWallet
        self.note = note
        self.iconName = iconName
        self.colorIdentifier = colorIdentifier
    }
}

/// Savings goals and their contributions. Goals are earmarks: nothing here
/// changes a wallet balance, a transaction or net worth.
public struct SavingsService {
    private let context: ModelContext
    private let calendar: CalendarPolicy
    private let now: () -> Date

    public init(context: ModelContext, calendar: CalendarPolicy = CalendarPolicy(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    // MARK: Goals

    @discardableResult
    public func create(_ draft: SavingsGoalDraft) throws -> SavingsGoal {
        let name = try validate(draft)
        let goal = SavingsGoal(
            name: name,
            target: draft.target,
            targetDate: draft.targetDate.map { calendar.calendar.startOfDay(for: $0) },
            linkedWalletID: draft.linkedWallet?.id,
            note: TextRules.optionalText(draft.note),
            iconName: draft.iconName,
            colorIdentifier: draft.colorIdentifier,
            sortOrder: try nextSortOrder(),
            createdAt: now()
        )
        context.insert(goal)
        try context.saveOrRollback()
        return goal
    }

    public func update(_ goal: SavingsGoal, with draft: SavingsGoalDraft) throws {
        let name = try validate(draft)
        if draft.target.currency.code != goal.currencyCode, !goal.contributionsNewestFirst.isEmpty {
            throw LedgerValidationError.goalCurrencyLocked
        }
        goal.name = name
        goal.targetAmountMinorUnits = draft.target.minorUnits
        goal.currencyCode = draft.target.currency.code
        goal.targetDate = draft.targetDate.map { calendar.calendar.startOfDay(for: $0) }
        goal.linkedWalletID = draft.linkedWallet?.id
        goal.note = TextRules.optionalText(draft.note)
        goal.iconName = draft.iconName
        goal.colorIdentifier = draft.colorIdentifier
        goal.updatedAt = now()
        try context.saveOrRollback()
    }

    public func setCompleted(_ goal: SavingsGoal, _ completed: Bool) throws {
        goal.completedAt = completed ? now() : nil
        goal.updatedAt = now()
        try context.saveOrRollback()
    }

    public func archive(_ goal: SavingsGoal) throws {
        guard !goal.isArchived else { return }
        goal.archivedAt = now()
        goal.updatedAt = now()
        try context.saveOrRollback()
    }

    public func restore(_ goal: SavingsGoal) throws {
        guard goal.isArchived else { return }
        goal.archivedAt = nil
        goal.updatedAt = now()
        try context.saveOrRollback()
    }

    /// Deletes the goal and its contribution history. Balances are unaffected.
    public func delete(_ goal: SavingsGoal) throws {
        context.delete(goal)
        try context.saveOrRollback()
    }

    // MARK: Contributions

    /// Records money set aside for (or taken back from) the goal.
    @discardableResult
    public func addEntry(
        to goal: SavingsGoal,
        amount: Money,
        isWithdrawal: Bool,
        date: Date,
        note: String? = nil
    ) throws -> SavingsContribution {
        let saved = try progress(of: goal, at: now()).saved
        let signed = try SavingsRules.signedEntry(amount: amount, isWithdrawal: isWithdrawal, saved: saved)
        let contribution = SavingsContribution(
            amountMinorUnits: signed.minorUnits,
            date: date,
            dayKey: calendar.dayKey(for: date),
            note: TextRules.optionalText(note),
            createdAt: now()
        )
        context.insert(contribution)
        contribution.goal = goal
        goal.updatedAt = now()
        try context.saveOrRollback()
        return contribution
    }

    /// Removing a contribution may not leave the goal with a negative saved amount.
    public func delete(_ contribution: SavingsContribution) throws {
        if let goal = contribution.goal {
            let remaining = goal.contributionsNewestFirst.filter { $0.id != contribution.id }
            let total = remaining.reduce(Int64(0)) { $0 + $1.amountMinorUnits }
            guard total >= 0 else { throw LedgerValidationError.withdrawalExceedsSavings }
        }
        context.delete(contribution)
        try context.saveOrRollback()
    }

    // MARK: Reads

    public func progress(of goal: SavingsGoal, at reference: Date) throws -> SavingsProgress {
        guard let target = goal.target else { throw LedgerValidationError.corruptRecord }
        let entries = goal.contributionsNewestFirst.map {
            Money(minorUnits: $0.amountMinorUnits, currency: target.currency)
        }
        return try SavingsRules.progress(
            target: target, entries: entries, targetDate: goal.targetDate, reference: reference, policy: calendar
        )
    }

    public func linkedWallet(of goal: SavingsGoal) throws -> Wallet? {
        guard let id = goal.linkedWalletID else { return nil }
        return try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == id })).first
    }

    /// Total earmarked by active goals linked to `wallet`, and whether it is
    /// more than the wallet holds (a warning; money is not moved).
    public func allocation(of wallet: Wallet) throws -> (allocated: Money, exceedsBalance: Bool)? {
        guard let currency = wallet.currency else { return nil }
        let walletID: UUID? = wallet.id
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>(predicate: #Predicate {
            $0.linkedWalletID == walletID && $0.archivedAt == nil
        }))
        guard !goals.isEmpty else { return nil }
        let allocated = try Money.sum(
            goals.filter { $0.currencyCode == currency.code }.map { try progress(of: $0, at: now()).saved },
            currency: currency
        )
        return (allocated, allocated.minorUnits > (try wallet.currentBalance()).minorUnits)
    }

    // MARK: Private

    private func validate(_ draft: SavingsGoalDraft) throws -> String {
        let name = try TextRules.normalizedName(draft.name)
        guard draft.target.isPositive else { throw LedgerValidationError.nonPositiveAmount }
        if let wallet = draft.linkedWallet, wallet.currencyCode != draft.target.currency.code {
            throw LedgerValidationError.currencyMismatch(
                walletCurrency: wallet.currencyCode, amountCurrency: draft.target.currency.code
            )
        }
        return name
    }

    private func nextSortOrder() throws -> Int {
        var descriptor = FetchDescriptor<SavingsGoal>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortOrder ?? -1) + 1
    }
}

enum SavingsReferences {
    static func isWalletLinked(_ wallet: Wallet, in context: ModelContext) throws -> Bool {
        let walletID: UUID? = wallet.id
        return try context.fetchCount(FetchDescriptor<SavingsGoal>(predicate: #Predicate {
            $0.linkedWalletID == walletID
        })) > 0
    }
}
