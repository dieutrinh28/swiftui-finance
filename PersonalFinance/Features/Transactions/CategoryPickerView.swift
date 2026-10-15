import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Pick an active category of the given type, or create a new one in place.
struct CategoryPickerView: View {
    let type: CategoryType
    @Binding var selection: LedgerCategory?

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<LedgerCategory> { $0.archivedAt == nil }, sort: \LedgerCategory.sortOrder)
    private var categories: [LedgerCategory]

    @State private var showingNewCategory = false

    var body: some View {
        List {
            Section {
                ForEach(categories.filter { $0.type == type }.inHierarchy(), id: \.category.id) { item in
                    let category = item.category
                    Button {
                        selection = category
                        dismiss()
                    } label: {
                        HStack(spacing: Spacing.md) {
                            CategoryRow(category: category, level: item.level)
                            Spacer()
                            if selection?.id == category.id {
                                Image(systemName: "checkmark")
                                    .font(.checkmark)
                                    .foregroundStyle(AppColor.accent)
                            }
                        }
                    }
                    .accessibilityAddTraits(selection?.id == category.id ? .isSelected : [])
                }
            }
            .surfaceRows()
            Section {
                Button {
                    showingNewCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
            }
            .surfaceRows()
        }
        .appGroupedStyle()
        .navigationTitle(type == .expense ? "Expense Category" : "Income Category")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewCategory) {
            CategoryFormView(mode: .create(type: type)) { created in
                selection = created
                dismiss()
            }
        }
    }
}

/// The label of a form's "Category" row: the chosen category ("Food & Drinks /
/// Coffee" for a sub-category) with its icon, or "Required".
struct CategoryFieldLabel: View {
    let category: LedgerCategory?

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text("Category")
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: Spacing.sm)
            if let category {
                HStack(spacing: Spacing.sm) {
                    Text(verbatim: category.path)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.trailing)
                    IconBadge(systemName: category.iconName,
                              tint: PaletteColor(identifier: category.colorIdentifier).color)
                }
            } else {
                Label("Required", systemImage: "exclamationmark.circle")
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .emptyStore) {
    @Previewable @State var selection: LedgerCategory?
    NavigationStack {
        CategoryPickerView(type: .expense, selection: $selection)
    }
}
