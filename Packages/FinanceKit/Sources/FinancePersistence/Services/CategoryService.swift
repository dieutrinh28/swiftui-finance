import Foundation
import SwiftData
import FinanceDomain

public struct CategoryDraft: Sendable, Equatable {
    public var name: String
    public var type: CategoryType
    public var iconName: String
    public var colorIdentifier: String

    public init(name: String, type: CategoryType, iconName: String, colorIdentifier: String) {
        self.name = name
        self.type = type
        self.iconName = iconName
        self.colorIdentifier = colorIdentifier
    }
}

/// Creates, edits, archives and deletes categories. Editing a category never
/// rewrites the transactions that use it.
public struct CategoryService {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    @discardableResult
    public func create(_ draft: CategoryDraft) throws -> LedgerCategory {
        let category = LedgerCategory(
            name: try TextRules.normalizedName(draft.name),
            type: draft.type,
            iconName: draft.iconName,
            colorIdentifier: draft.colorIdentifier,
            sortOrder: try nextSortOrder(),
            createdAt: now()
        )
        context.insert(category)
        try context.saveOrRollback()
        return category
    }

    public func update(_ category: LedgerCategory, with draft: CategoryDraft) throws {
        let name = try TextRules.normalizedName(draft.name)
        if category.type != draft.type, category.hasHistory {
            throw LedgerValidationError.categoryTypeLocked
        }
        category.name = name
        category.typeRaw = draft.type.rawValue
        category.iconName = draft.iconName
        category.colorIdentifier = draft.colorIdentifier
        category.updatedAt = now()
        try context.saveOrRollback()
    }

    /// Hidden from pickers; existing transactions keep it.
    public func archive(_ category: LedgerCategory) throws {
        guard !category.isArchived else { return }
        let timestamp = now()
        category.archivedAt = timestamp
        category.updatedAt = timestamp
        try context.saveOrRollback()
    }

    public func restore(_ category: LedgerCategory) throws {
        guard category.isArchived else { return }
        category.archivedAt = nil
        category.updatedAt = now()
        try context.saveOrRollback()
    }

    /// Only categories without transactions and not part of a budget can be deleted.
    public func delete(_ category: LedgerCategory) throws {
        guard !category.hasHistory else { throw LedgerValidationError.categoryHasHistory }
        guard try !BudgetReferences.isCategoryUsed(category, in: context) else {
            throw LedgerValidationError.categoryUsedByBudget
        }
        guard try !RecurringReferences.isCategoryUsed(category, in: context) else {
            throw LedgerValidationError.categoryUsedByRecurring
        }
        context.delete(category)
        try context.saveOrRollback()
    }

    private func nextSortOrder() throws -> Int {
        var descriptor = FetchDescriptor<LedgerCategory>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortOrder ?? -1) + 1
    }
}
