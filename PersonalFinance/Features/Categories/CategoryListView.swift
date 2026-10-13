import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

/// Categories grouped by type, with archived ones at the bottom.
struct CategoryListView: View {
    @Query(sort: \LedgerCategory.sortOrder)
    private var categories: [LedgerCategory]

    @State private var showingNewCategory = false

    var body: some View {
        List {
            ForEach([CategoryType.expense, .income], id: \.self) { type in
                let matching = categories.filter { $0.type == type && !$0.isArchived }
                if !matching.isEmpty {
                    Section(type.displayName) {
                        ForEach(matching) { category in
                            NavigationLink(value: category) {
                                CategoryRow(category: category)
                            }
                        }
                    }
                }
            }
            let archived = categories.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { category in
                        NavigationLink(value: category) {
                            CategoryRow(category: category)
                        }
                    }
                }
            }
        }
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView("No categories", systemImage: "square.grid.2x2")
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewCategory) {
            CategoryFormView(mode: .create(type: .expense))
        }
    }
}

struct CategoryRow: View {
    let category: LedgerCategory

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(systemName: category.iconName,
                      tint: PaletteColor(identifier: category.colorIdentifier).color)
            Text(category.name)
        }
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        CategoryListView()
            .financeDestinations()
    }
}
