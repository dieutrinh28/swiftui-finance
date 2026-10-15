import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Create or edit a category. Logic lives in `CategoryFormModel`; changes are
/// applied through `CategoryService` on Save.
struct CategoryFormView: View {
    let mode: CategoryFormModel.Mode
    var onSaved: ((LedgerCategory) -> Void)? = nil

    @Environment(AppContainer.self) private var app
    @State private var model: CategoryFormModel?

    var body: some View {
        Group {
            if let model {
                CategoryFormContent(model: model, onSaved: onSaved)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = CategoryFormModel(mode: mode, service: app.categories)
        }
    }
}

private struct CategoryFormContent: View {
    @Bindable var model: CategoryFormModel
    let onSaved: ((LedgerCategory) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerCategory.sortOrder) private var allCategories: [LedgerCategory]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $model.type) {
                        Text("Expense").tag(CategoryType.expense)
                        Text("Income").tag(CategoryType.income)
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.typeLocked)
                } footer: {
                    if model.typeLocked {
                        Text("This category has transactions or sub-categories, so its type can't change.")
                    }
                }
                .surfaceRows()

                Section {
                    Picker("Parent category", selection: $model.parent) {
                        Text("None (top level)").tag(LedgerCategory?.none)
                        ForEach(model.possibleParents(from: allCategories)) { candidate in
                            Text(verbatim: candidate.name).tag(Optional(candidate))
                        }
                    }
                    .disabled(model.hasSubcategories)
                } footer: {
                    if model.hasSubcategories {
                        Text("This category has sub-categories, so it stays at the top level.")
                    } else {
                        Text("A sub-category is counted in its parent's budgets and reports, and shown under it.")
                    }
                }
                .surfaceRows()

                if model.showsIrregular {
                    Section {
                        Toggle("Irregular by default", isOn: $model.isIrregular)
                            .tint(AppColor.accent)
                    } footer: {
                        Text("New expenses in this category start as irregular, for example Travel. They lower the balance but are not counted as spending or in budgets. Existing expenses keep their setting.")
                    }
                    .surfaceRows()
                }

                Section("Appearance") {
                    HStack {
                        Spacer()
                        IconBadge(systemName: model.iconName, tint: PaletteColor(identifier: model.colorIdentifier).color,
                                  size: .large)
                            .padding(.vertical, Spacing.sm)
                        Spacer()
                    }
                    SymbolPicker(
                        selection: $model.iconName,
                        symbols: SymbolCatalog.categories,
                        tint: PaletteColor(identifier: model.colorIdentifier).color
                    )
                    PalettePicker(selection: $model.colorIdentifier)
                }
                .surfaceRows()
            }
            .appGroupedStyle()
            .keyboardDismissal()
            .safeAreaInset(edge: .bottom) {
                PrimaryActionBar(title: model.isEditing ? "Save Changes" : "Save Category", isEnabled: model.canSave) {
                    if let saved = model.save() {
                        onSaved?(saved)
                        dismiss()
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .errorAlert(Binding(
                get: { model.failure.map { AlertError($0) } },
                set: { if $0 == nil { model.clearFailure() } }
            ))
        }
    }
}

#Preview(traits: .emptyStore) {
    CategoryFormView(mode: .create(type: .expense))
}
