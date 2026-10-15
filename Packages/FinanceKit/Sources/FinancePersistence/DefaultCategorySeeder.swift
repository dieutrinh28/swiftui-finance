import Foundation
import SwiftData
import FinanceDomain

/// Languages the built-in category names exist in.
public enum SeedLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case vietnamese = "vi"
    case japanese = "ja"

    /// The language of a localization identifier such as "vi", "vi-VN" or
    /// "en_GB"; English for anything else.
    public init(localization: String?) {
        let code = localization?
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map { $0.lowercased() }
        self = code.flatMap(SeedLanguage.init(rawValue:)) ?? .english
    }
}

public struct DefaultCategory: Hashable, Sendable {
    public let seedKey: String
    /// English name (the development language).
    public let name: String
    public let vietnameseName: String
    public let japaneseName: String
    public let type: CategoryType
    public let iconName: String
    public let colorIdentifier: String

    public func name(in language: SeedLanguage) -> String {
        switch language {
        case .english: name
        case .vietnamese: vietnameseName
        case .japanese: japaneseName
        }
    }

    /// Every name this category has been seeded with, in any language.
    public var allNames: [String] { SeedLanguage.allCases.map(name(in:)) }
}

/// Creates the built-in, editable categories on first launch, in the app's
/// language, and keeps untouched ones in the app's language afterwards.
///
/// Names are stored data, not looked up at display time: a category the user
/// renames keeps its name in every language. A built-in category counts as
/// untouched while its name still equals one of its seed names.
public enum DefaultCategorySeeder {
    public static let expenseCategories: [DefaultCategory] = [
        .init(seedKey: "expense.food", name: "Food & Drinks", vietnameseName: "Ăn uống", japaneseName: "食費", type: .expense, iconName: "fork.knife", colorIdentifier: "orange"),
        .init(seedKey: "expense.housing", name: "Housing", vietnameseName: "Nhà ở", japaneseName: "住居費", type: .expense, iconName: "house", colorIdentifier: "brown"),
        .init(seedKey: "expense.transportation", name: "Transportation", vietnameseName: "Đi lại", japaneseName: "交通費", type: .expense, iconName: "car", colorIdentifier: "blue"),
        .init(seedKey: "expense.shopping", name: "Shopping", vietnameseName: "Mua sắm", japaneseName: "買い物", type: .expense, iconName: "bag", colorIdentifier: "pink"),
        .init(seedKey: "expense.health", name: "Health", vietnameseName: "Sức khoẻ", japaneseName: "医療・健康", type: .expense, iconName: "cross.case", colorIdentifier: "red"),
        .init(seedKey: "expense.fitness", name: "Sports & Fitness", vietnameseName: "Thể thao", japaneseName: "スポーツ", type: .expense, iconName: "figure.run", colorIdentifier: "green"),
        .init(seedKey: "expense.education", name: "Education", vietnameseName: "Học tập", japaneseName: "教育", type: .expense, iconName: "graduationcap", colorIdentifier: "indigo"),
        .init(seedKey: "expense.entertainment", name: "Entertainment", vietnameseName: "Giải trí", japaneseName: "娯楽", type: .expense, iconName: "tv", colorIdentifier: "purple"),
        .init(seedKey: "expense.travel", name: "Travel", vietnameseName: "Du lịch", japaneseName: "旅行", type: .expense, iconName: "airplane", colorIdentifier: "cyan"),
        .init(seedKey: "expense.bills", name: "Bills & Utilities", vietnameseName: "Hoá đơn & Tiện ích", japaneseName: "水道光熱・通信費", type: .expense, iconName: "bolt", colorIdentifier: "yellow"),
        .init(seedKey: "expense.personalCare", name: "Personal Care", vietnameseName: "Chăm sóc cá nhân", japaneseName: "美容・身だしなみ", type: .expense, iconName: "scissors", colorIdentifier: "mint"),
        .init(seedKey: "expense.family", name: "Family", vietnameseName: "Gia đình", japaneseName: "家族", type: .expense, iconName: "figure.2.and.child.holdinghands", colorIdentifier: "teal"),
        .init(seedKey: "expense.other", name: "Other Expenses", vietnameseName: "Chi tiêu khác", japaneseName: "その他の支出", type: .expense, iconName: "ellipsis.circle", colorIdentifier: "gray"),
    ]

    public static let incomeCategories: [DefaultCategory] = [
        .init(seedKey: "income.salary", name: "Salary", vietnameseName: "Lương", japaneseName: "給与", type: .income, iconName: "banknote", colorIdentifier: "green"),
        .init(seedKey: "income.freelance", name: "Freelance", vietnameseName: "Làm tự do", japaneseName: "副業", type: .income, iconName: "laptopcomputer", colorIdentifier: "teal"),
        .init(seedKey: "income.business", name: "Business", vietnameseName: "Kinh doanh", japaneseName: "事業収入", type: .income, iconName: "briefcase", colorIdentifier: "blue"),
        .init(seedKey: "income.investment", name: "Investment Returns", vietnameseName: "Lợi nhuận đầu tư", japaneseName: "投資収益", type: .income, iconName: "chart.line.uptrend.xyaxis", colorIdentifier: "indigo"),
        .init(seedKey: "income.gifts", name: "Gifts", vietnameseName: "Quà tặng", japaneseName: "贈与・お祝い", type: .income, iconName: "gift", colorIdentifier: "pink"),
        .init(seedKey: "income.other", name: "Other Income", vietnameseName: "Thu nhập khác", japaneseName: "その他の収入", type: .income, iconName: "plus.circle", colorIdentifier: "gray"),
    ]

    public static var all: [DefaultCategory] { expenseCategories + incomeCategories }

    public static func category(seedKey: String) -> DefaultCategory? {
        all.first { $0.seedKey == seedKey }
    }

    /// The built-in category of `type` that has `name` in any language,
    /// compared with `fold` (e.g. ignoring case and accents).
    public static func category(
        named name: String,
        type: CategoryType,
        fold: (String) -> String = { $0 }
    ) -> DefaultCategory? {
        let key = fold(name)
        return all.first { $0.type == type && $0.allNames.contains { fold($0) == key } }
    }

    /// Inserts the defaults only when the store has no categories at all.
    ///
    /// Idempotent: running it again does nothing, and it never recreates or
    /// overwrites categories the user has renamed or archived.
    /// - Returns: the number of categories inserted.
    @discardableResult
    public static func seedIfNeeded(
        in context: ModelContext,
        language: SeedLanguage = .english,
        now: Date = .now
    ) throws -> Int {
        guard try context.fetchCount(FetchDescriptor<LedgerCategory>()) == 0 else { return 0 }

        for (index, item) in all.enumerated() {
            context.insert(LedgerCategory(
                name: item.name(in: language),
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

    /// Renames built-in categories the user never renamed to their name in
    /// `language`, so switching the app's language also switches them.
    ///
    /// Only the name changes: transactions, budgets and recurring items refer
    /// to categories by identity, so nothing else is affected. A category whose
    /// name is not one of its seed names is left exactly as the user wrote it.
    /// - Returns: the number of categories renamed.
    @discardableResult
    public static func localizeUntouched(in context: ModelContext, to language: SeedLanguage) throws -> Int {
        let seeded = try context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.seedKey != nil }))
        var renamed = 0
        for category in seeded {
            guard let seedKey = category.seedKey,
                  let item = self.category(seedKey: seedKey),
                  item.allNames.contains(category.name)
            else { continue }
            let target = item.name(in: language)
            if category.name != target {
                category.name = target
                renamed += 1
            }
        }
        if renamed > 0 { try context.saveOrRollback() }
        return renamed
    }
}
