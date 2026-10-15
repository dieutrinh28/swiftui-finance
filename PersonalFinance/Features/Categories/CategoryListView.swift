import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Categories grouped by type, sub-categories under their parent, archived
/// ones at the bottom.
struct CategoryListView: View {
    @Query(sort: \LedgerCategory.sortOrder)
    private var categories: [LedgerCategory]

    @State private var showingNewCategory = false

    var body: some View {
        List {
            ForEach([CategoryType.expense, .income], id: \.self) { type in
                let matching = categories.filter { $0.type == type && !$0.isArchived }.inHierarchy()
                if !matching.isEmpty {
                    Section(type.displayName) {
                        ForEach(matching, id: \.category.id) { item in
                            NavigationLink(value: item.category) {
                                CategoryRow(category: item.category, level: item.level)
                            }
                        }
                    }
                    .surfaceRows()
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
                .surfaceRows()
            }
        }
        .appGroupedStyle()
        .overlay {
            if categories.isEmpty {
                EmptyStateView(
                    systemImage: "square.grid.2x2",
                    title: "No categories",
                    message: "Add categories to sort your income and expenses."
                ) {
                    Button("Add Category", systemImage: "plus") { showingNewCategory = true }
                        .buttonStyle(.appPrimary)
                }
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

/// A category with its icon; sub-categories (level 1) are indented under
/// their parent. Shows when new expenses in it start as irregular.
struct CategoryRow: View {
    let category: LedgerCategory
    var level = 0

    @ScaledMetric(relativeTo: .body) private var indent = 28

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconBadge(systemName: category.iconName,
                      tint: PaletteColor(identifier: category.colorIdentifier).color,
                      size: level > 0 ? .small : .regular)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: category.name)
                    .font(.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                if category.isIrregular {
                    Text("Irregular by default")
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.leading, CGFloat(level) * indent)
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        CategoryListView()
            .financeDestinations()
    }
}
