import Foundation
import SwiftData
import FinanceDomain

public struct CategoryDraft {
    public var name: String
    public var type: CategoryType
    public var iconName: String
    public var colorIdentifier: String
    /// A top-level category of the same type, or nil for a top-level category.
    public var parent: LedgerCategory?
    /// Expense categories only: new expenses in it start as irregular.
    public var isIrregular: Bool

    public init(
        name: String,
        type: CategoryType,
        iconName: String,
        colorIdentifier: String,
        parent: LedgerCategory? = nil,
        isIrregular: Bool = false
    ) {
        self.name = name
        self.type = type
        self.iconName = iconName
        self.colorIdentifier = colorIdentifier
        self.parent = parent
        self.isIrregular = isIrregular
    }
}

/// Creates, edits, archives and deletes categories. Editing a category never
/// rewrites the transactions that use it (also not their irregular flag:
/// the category's flag is only the default for new expenses).
///
/// Sub-categories: two levels at most. A parent is a top-level category of
/// the same type; a category that has sub-categories can't become one.
public struct CategoryService {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    @discardableResult
    public func create(_ draft: CategoryDraft) throws -> LedgerCategory {
        let name = try TextRules.normalizedName(draft.name)
        try validateParent(draft.parent, for: nil, type: draft.type)
        let category = LedgerCategory(
            name: name,
            type: draft.type,
            iconName: draft.iconName,
            colorIdentifier: draft.colorIdentifier,
            sortOrder: try nextSortOrder(),
            isIrregular: draft.type == .expense && draft.isIrregular,
            createdAt: now()
        )
        context.insert(category)
        category.parent = draft.parent
        try context.saveOrRollback()
        return category
    }

    public func update(_ category: LedgerCategory, with draft: CategoryDraft) throws {
        let name = try TextRules.normalizedName(draft.name)
        if category.type != draft.type {
            if category.hasHistory { throw LedgerValidationError.categoryTypeLocked }
            if try isReferenced(category) { throw LedgerValidationError.categoryTypeInUse }
        }
        try validateParent(draft.parent, for: category, type: draft.type)

        category.name = name
        category.typeRaw = draft.type.rawValue
        category.iconName = draft.iconName
        category.colorIdentifier = draft.colorIdentifier
        category.isIrregular = draft.type == .expense && draft.isIrregular
        category.parent = draft.parent
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

    /// Only categories without transactions and not part of a budget can be
    /// deleted. Their sub-categories become top-level categories.
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

    // MARK: Private

    /// Two levels, same type, never itself, and never moving a category that
    /// already has sub-categories under another one.
    private func validateParent(_ parent: LedgerCategory?, for category: LedgerCategory?, type: CategoryType) throws {
        guard let parent else { return }
        guard parent.id != category?.id,
              parent.parent == nil,
              parent.type == type
        else { throw LedgerValidationError.invalidParentCategory }
        if let category, !category.liveChildren.isEmpty {
            throw LedgerValidationError.categoryHasSubcategories
        }
        if parent.isArchived, parent.id != category?.parent?.id {
            throw LedgerValidationError.archivedCategory
        }
    }

    /// Used by a budget, a recurring item or sub-categories: switching
    /// between income and expense would break them.
    private func isReferenced(_ category: LedgerCategory) throws -> Bool {
        try !category.liveChildren.isEmpty
            || BudgetReferences.isCategoryUsed(category, in: context)
            || RecurringReferences.isCategoryUsed(category, in: context)
    }

    private func nextSortOrder() throws -> Int {
        var descriptor = FetchDescriptor<LedgerCategory>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortOrder ?? -1) + 1
    }
}

extension LedgerCategory {
    /// Sub-categories not deleted in the current context, in display order.
    public var liveChildren: [LedgerCategory] {
        children.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// "Food / Coffee" for a sub-category, "Food" otherwise.
    public var path: String {
        parent.map { "\($0.name) / \(name)" } ?? name
    }
}

extension Array where Element == LedgerCategory {
    /// Parents in their order, each followed by its sub-categories (level 1).
    /// A sub-category whose parent is not in the array is shown at level 0.
    public func inHierarchy() -> [(category: LedgerCategory, level: Int)] {
        let ids = Set(map(\.id))
        let byParent = Dictionary(grouping: filter { $0.parent.map { ids.contains($0.id) } ?? false },
                                  by: { $0.parent!.id })
        var result: [(category: LedgerCategory, level: Int)] = []
        for category in self where !(category.parent.map { ids.contains($0.id) } ?? false) {
            result.append((category, 0))
            for child in (byParent[category.id] ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
                result.append((child, 1))
            }
        }
        return result
    }
}
