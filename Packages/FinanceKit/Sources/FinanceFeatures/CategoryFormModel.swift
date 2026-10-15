import Foundation
import Observation
import FinanceDomain
import FinancePersistence

/// State and behaviour of the category form.
///
/// Rules kept here (and tested) instead of in the view:
/// - the type is locked once the category has transactions or sub-categories;
/// - changing the type drops a parent of the other type and the irregular flag
///   (only expense categories can be irregular);
/// - a parent is a top-level category of the same type, never the category itself;
///   a category with sub-categories stays at the top level;
/// - a new sub-category starts with its parent's type, icon, colour and irregular flag.
@MainActor
@Observable
public final class CategoryFormModel {
    public enum Mode {
        case create(type: CategoryType)
        /// A new sub-category under `of`.
        case createChild(of: LedgerCategory)
        case edit(LedgerCategory)
    }

    public let mode: Mode

    // MARK: Input

    public var name = ""

    /// Ignored while `typeLocked`. Drops a parent of the other type and, for
    /// income, the irregular flag.
    public var type: CategoryType {
        get { selectedType }
        set {
            guard !typeLocked, newValue != selectedType else { return }
            selectedType = newValue
            if selectedParent?.type != newValue { selectedParent = nil }
            if newValue != .expense { irregular = false }
        }
    }

    /// Ignores a category that can't be the parent (see `canBeParent`).
    public var parent: LedgerCategory? {
        get { selectedParent }
        set {
            if let newValue, !canBeParent(newValue) { return }
            if newValue != nil && hasSubcategories { return }
            selectedParent = newValue
        }
    }

    /// Expense categories only; ignored for income.
    public var isIrregular: Bool {
        get { irregular }
        set { irregular = selectedType == .expense ? newValue : false }
    }

    public var iconName = "ellipsis.circle"
    public var colorIdentifier = "blue"

    // MARK: Output

    public private(set) var failure: (any Error)?

    // MARK: Private

    private var selectedType: CategoryType = .expense
    private var selectedParent: LedgerCategory?
    private var irregular = false
    @ObservationIgnored private let service: CategoryService

    public init(mode: Mode, service: CategoryService) {
        self.mode = mode
        self.service = service

        switch mode {
        case .create(let initialType):
            selectedType = initialType
        case .createChild(let parentCategory):
            selectedType = parentCategory.type ?? .expense
            selectedParent = parentCategory
            iconName = parentCategory.iconName
            colorIdentifier = parentCategory.colorIdentifier
            irregular = selectedType == .expense && parentCategory.isIrregular
        case .edit(let category):
            name = category.name
            selectedType = category.type ?? .expense
            selectedParent = category.parent
            iconName = category.iconName
            colorIdentifier = category.colorIdentifier
            irregular = category.isIrregular
        }
    }

    // MARK: Derived state

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingCategory: LedgerCategory? {
        if case .edit(let category) = mode { return category }
        return nil
    }

    public var hasSubcategories: Bool { !(editingCategory?.liveChildren.isEmpty ?? true) }

    /// History or sub-categories fix the type. (Budgets and recurring items do
    /// too; the service explains that case if it happens.)
    public var typeLocked: Bool { (editingCategory?.hasHistory ?? false) || hasSubcategories }

    /// The irregular switch only applies to expense categories.
    public var showsIrregular: Bool { selectedType == .expense }

    /// A top-level category of the same type, not this one; archived only if it is already the parent.
    public func canBeParent(_ candidate: LedgerCategory) -> Bool {
        candidate.type == selectedType
            && candidate.parent == nil
            && candidate.id != editingCategory?.id
            && (!candidate.isArchived || candidate.id == selectedParent?.id)
    }

    /// The categories offered as parent, in the order given.
    public func possibleParents(from all: [LedgerCategory]) -> [LedgerCategory] {
        all.filter(canBeParent)
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Actions

    /// The saved category, or nil with `failure` set.
    @discardableResult
    public func save() -> LedgerCategory? {
        let draft = CategoryDraft(
            name: name, type: selectedType, iconName: iconName, colorIdentifier: colorIdentifier,
            parent: selectedParent, isIrregular: irregular
        )
        do {
            let saved: LedgerCategory
            switch mode {
            case .create, .createChild:
                saved = try service.create(draft)
            case .edit(let category):
                try service.update(category, with: draft)
                saved = category
            }
            failure = nil
            return saved
        } catch {
            failure = error
            return nil
        }
    }

    public func clearFailure() {
        failure = nil
    }
}
