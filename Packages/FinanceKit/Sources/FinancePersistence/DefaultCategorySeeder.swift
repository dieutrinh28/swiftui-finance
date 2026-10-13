import Foundation
import SwiftData
import FinanceDomain

public struct DefaultCategory: Hashable, Sendable {
    public let seedKey: String
    public let name: String
    public let type: CategoryType
    public let iconName: String
    public let colorIdentifier: String
}

/// Creates the built-in, editable categories on first launch.
public enum DefaultCategorySeeder {
    public static let expenseCategories: [DefaultCategory] = [
        .init(seedKey: "expense.food", name: "Food & Drinks", type: .expense, iconName: "fork.knife", colorIdentifier: "orange"),
        .init(seedKey: "expense.housing", name: "Housing", type: .expense, iconName: "house", colorIdentifier: "brown"),
        .init(seedKey: "expense.transportation", name: "Transportation", type: .expense, iconName: "car", colorIdentifier: "blue"),
        .init(seedKey: "expense.shopping", name: "Shopping", type: .expense, iconName: "bag", colorIdentifier: "pink"),
        .init(seedKey: "expense.health", name: "Health", type: .expense, iconName: "cross.case", colorIdentifier: "red"),
        .init(seedKey: "expense.fitness", name: "Sports & Fitness", type: .expense, iconName: "figure.run", colorIdentifier: "green"),
        .init(seedKey: "expense.education", name: "Education", type: .expense, iconName: "graduationcap", colorIdentifier: "indigo"),
        .init(seedKey: "expense.entertainment", name: "Entertainment", type: .expense, iconName: "tv", colorIdentifier: "purple"),
        .init(seedKey: "expense.travel", name: "Travel", type: .expense, iconName: "airplane", colorIdentifier: "cyan"),
        .init(seedKey: "expense.bills", name: "Bills & Utilities", type: .expense, iconName: "bolt", colorIdentifier: "yellow"),
        .init(seedKey: "expense.personalCare", name: "Personal Care", type: .expense, iconName: "scissors", colorIdentifier: "mint"),
        .init(seedKey: "expense.family", name: "Family", type: .expense, iconName: "figure.2.and.child.holdinghands", colorIdentifier: "teal"),
        .init(seedKey: "expense.other", name: "Other Expenses", type: .expense, iconName: "ellipsis.circle", colorIdentifier: "gray"),
    ]

    public static let incomeCategories: [DefaultCategory] = [
        .init(seedKey: "income.salary", name: "Salary", type: .income, iconName: "banknote", colorIdentifier: "green"),
        .init(seedKey: "income.freelance", name: "Freelance", type: .income, iconName: "laptopcomputer", colorIdentifier: "teal"),
        .init(seedKey: "income.business", name: "Business", type: .income, iconName: "briefcase", colorIdentifier: "blue"),
        .init(seedKey: "income.investment", name: "Investment Returns", type: .income, iconName: "chart.line.uptrend.xyaxis", colorIdentifier: "indigo"),
        .init(seedKey: "income.gifts", name: "Gifts", type: .income, iconName: "gift", colorIdentifier: "pink"),
        .init(seedKey: "income.other", name: "Other Income", type: .income, iconName: "plus.circle", colorIdentifier: "gray"),
    ]

    public static var all: [DefaultCategory] { expenseCategories + incomeCategories }

    /// Inserts the defaults only when the store has no categories at all.
    ///
    /// Idempotent: running it again does nothing, and it never recreates or
    /// overwrites categories the user has renamed or archived.
    /// - Returns: the number of categories inserted.
    @discardableResult
    public static func seedIfNeeded(in context: ModelContext, now: Date = .now) throws -> Int {
        guard try context.fetchCount(FetchDescriptor<LedgerCategory>()) == 0 else { return 0 }

        for (index, item) in all.enumerated() {
            context.insert(LedgerCategory(
                name: item.name,
                type: item.type,
                iconName: item.iconName,
                colorIdentifier: item.colorIdentifier,
                seedKey: item.seedKey,
                sortOrder: index,
                createdAt: now
            ))
        }
        try context.saveOrRollback()
        return all.count
    }
}
