import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

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
                ForEach(categories.filter { $0.type == type }) { category in
                    Button {
                        selection = category
                        dismiss()
                    } label: {
                        HStack(spacing: Spacing.md) {
                            IconBadge(systemName: category.iconName,
                                      tint: PaletteColor(identifier: category.colorIdentifier).color)
                            Text(category.name)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if selection?.id == category.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    showingNewCategory = true
                } label: {
                    Label("New Category", systemImage: "plus")
                }
            }
        }
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

#Preview(traits: .emptyStore) {
    @Previewable @State var selection: LedgerCategory?
    NavigationStack {
        CategoryPickerView(type: .expense, selection: $selection)
    }
}
