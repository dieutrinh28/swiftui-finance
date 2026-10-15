import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// A category's transaction history, with edit, archive and delete.
struct CategoryDetailView: View {
    let category: LedgerCategory

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingNewChild = false
    @State private var confirmingDelete = false
    @State private var error: AlertError?

    var body: some View {
        if category.isDeleted || category.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                HStack(spacing: Spacing.md) {
                    IconBadge(systemName: category.iconName,
                              tint: PaletteColor(identifier: category.colorIdentifier).color, size: .large)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: category.name)
                            .font(.cardTitle)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(category.type?.displayName ?? String(localized: "Unknown type", bundle: .l10n))
                            .font(.meta)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(.vertical, Spacing.xs)
                if let parent = category.parent {
                    NavigationLink(value: parent) {
                        LabeledContent("Sub-category of") { Text(verbatim: parent.name) }
                    }
                }
                if category.isIrregular {
                    Label("New expenses start as irregular: not counted as spending or in budgets.", systemImage: "sparkles")
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                }
                if category.isArchived {
                    Label("Archived: hidden when choosing a category.", systemImage: "archivebox")
                        .font(.meta)
                        .foregroundStyle(AppColor.warning)
                }
            }
            .highlightedRows()

            if category.parent == nil, category.type != nil {
                Section("Sub-categories") {
                    ForEach(category.liveChildren) { child in
                        NavigationLink(value: child) {
                            CategoryRow(category: child)
                        }
                    }
                    if !category.isArchived {
                        Button("Add Sub-category", systemImage: "plus") { showingNewChild = true }
                    }
                }
                .surfaceRows()
            }

            Section {
                let history = category.transactionsIncludingSubcategoriesNewestFirst
                if history.isEmpty {
                    Text("No transactions use this category yet.")
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(history) { transaction in
                        NavigationLink(value: transaction) {
                            TransactionRow(transaction: transaction, showsDate: true)
                        }
                    }
                }
            } header: {
                Text("Transactions")
            } footer: {
                if !category.liveChildren.isEmpty {
                    Text("Includes the transactions of its sub-categories.")
                }
            }
            .surfaceRows()
        }
        .appGroupedStyle()
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {  // not .secondaryAction: iOS nests that in its own "…" overflow menu
                Menu {
                    Button("Edit Category", systemImage: "pencil") { showingEdit = true }
                    if category.isArchived {
                        Button("Restore Category", systemImage: "arrow.uturn.backward") {
                            perform { try app.categories.restore(category) }
                        }
                    } else {
                        Button("Archive Category", systemImage: "archivebox") {
                            perform { try app.categories.archive(category) }
                        }
                    }
                    if !category.hasHistory {
                        Button("Delete Category", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            CategoryFormView(mode: .edit(category))
        }
        .sheet(isPresented: $showingNewChild) {
            CategoryFormView(mode: .createChild(of: category))
        }
        .confirmationDialog("Delete \(category.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Category", role: .destructive) {
                perform {
                    try app.categories.delete(category)
                    dismiss()
                }
            }
        } message: {
            Text("No transactions use this category. This can't be undone.")
        }
        .errorAlert($error)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = AlertError(error) }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query(sort: \LedgerCategory.sortOrder) var categories: [LedgerCategory]
    NavigationStack {
        if let category = categories.first {
            CategoryDetailView(category: category)
                .financeDestinations()
        }
    }
}
