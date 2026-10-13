import SwiftUI
import FinanceDomain
import FinancePersistence

/// Create or edit a category. Changes are applied through `CategoryService` on Save.
struct CategoryFormView: View {
    enum Mode {
        case create(type: CategoryType)
        case edit(LedgerCategory)
    }

    let mode: Mode
    var onSaved: ((LedgerCategory) -> Void)? = nil

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: CategoryType = .expense
    @State private var iconName = "ellipsis.circle"
    @State private var colorIdentifier = PaletteColor.blue.rawValue
    @State private var didLoad = false
    @State private var error: AlertError?

    private var editingCategory: LedgerCategory? {
        if case .edit(let category) = mode { return category }
        return nil
    }

    private var typeLocked: Bool { editingCategory?.hasHistory ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $type) {
                        Text("Expense").tag(CategoryType.expense)
                        Text("Income").tag(CategoryType.income)
                    }
                    .pickerStyle(.segmented)
                    .disabled(typeLocked)
                } footer: {
                    if typeLocked {
                        Text("This category is used by transactions, so its type can't change.")
                    }
                }

                Section("Appearance") {
                    HStack {
                        Spacer()
                        IconBadge(systemName: iconName, tint: PaletteColor(identifier: colorIdentifier).color)
                            .scaleEffect(1.4)
                            .padding(.vertical, Spacing.sm)
                        Spacer()
                    }
                    SymbolPicker(
                        selection: $iconName,
                        symbols: SymbolCatalog.categories,
                        tint: PaletteColor(identifier: colorIdentifier).color
                    )
                    PalettePicker(selection: $colorIdentifier)
                }
            }
            .navigationTitle(editingCategory == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .errorAlert($error)
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        switch mode {
        case .create(let initialType):
            type = initialType
        case .edit(let category):
            name = category.name
            type = category.type ?? .expense
            iconName = category.iconName
            colorIdentifier = category.colorIdentifier
        }
    }

    private func save() {
        let draft = CategoryDraft(name: name, type: type, iconName: iconName, colorIdentifier: colorIdentifier)
        do {
            let saved: LedgerCategory
            if let category = editingCategory {
                try app.categories.update(category, with: draft)
                saved = category
            } else {
                saved = try app.categories.create(draft)
            }
            onSaved?(saved)
            dismiss()
        } catch {
            self.error = AlertError(error)
        }
    }
}

#Preview(traits: .emptyStore) {
    CategoryFormView(mode: .create(type: .expense))
}
