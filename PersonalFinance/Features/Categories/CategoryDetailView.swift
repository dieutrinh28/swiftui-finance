import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

/// A category's transaction history, with edit, archive and delete.
struct CategoryDetailView: View {
    let category: LedgerCategory

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
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
                              tint: PaletteColor(identifier: category.colorIdentifier).color)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(category.name).font(.headline)
                        Text(category.type?.displayName ?? String(localized: "Unknown type"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if category.isArchived {
                    Label("Archived: hidden when choosing a category.", systemImage: "archivebox")
                        .font(.footnote)
                        .foregroundStyle(AppColor.liability)
                }
            }

            Section("Transactions") {
                let history = category.transactionsNewestFirst
                if history.isEmpty {
                    Text("No transactions use this category yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history) { transaction in
                        NavigationLink(value: transaction) {
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
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
