import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Review recurring items that are due: record each (optionally with a
/// different amount) or skip it. Nothing is recorded automatically.
struct DueOccurrencesView: View {
    @Environment(AppContainer.self) private var app

    @State private var due: [DueOccurrence] = []
    @State private var adjusting: DueOccurrence?
    @State private var error: AlertError?

    var body: some View {
        List {
            if due.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "Nothing due",
                    message: "All recurring transactions are up to date."
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(due) { item in
                        DueRow(item: item)
                            .swipeActions(edge: .trailing) {
                                Button("Skip") { perform { try app.recurring.skip(item) } }
                                    .tint(AppColor.neutralAction)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Record") { perform { try app.recurring.record(item) } }
                                    .tint(AppColor.accent)
                            }
                            .contextMenu {
                                Button("Record", systemImage: "checkmark") { perform { try app.recurring.record(item) } }
                                Button("Record a Different Amount", systemImage: "pencil") { adjusting = item }
                                Button("Skip", systemImage: "forward") { perform { try app.recurring.skip(item) } }
                            }
                    }
                } footer: {
                    Text("Swipe right to record, left to skip, or touch and hold for more. Each occurrence can be recorded only once.")
                }
                .surfaceRows()
            }
        }
        .appGroupedStyle()
        .navigationTitle("Due")
        .toolbar {
            if due.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Menu("All") {
                        Button("Record All", systemImage: "checkmark.circle") { recordAll() }
                        Button("Skip All", systemImage: "forward") {
                            perform { for item in due { try app.recurring.skip(item) } }
                        }
                    }
                }
            }
        }
        .task(id: app.dataVersion) { reload() }
        .sheet(item: $adjusting) { item in
            RecordOccurrenceFormView(item: item)
        }
        .errorAlert($error)
    }

    private func reload() {
        do { due = try app.recurring.dueOccurrences(at: .now) } catch { self.error = AlertError(error) }
    }

    /// Records each item; stops at the first failure so nothing is half-done silently.
    private func recordAll() {
        perform { for item in due { try app.recurring.record(item) } }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = AlertError(error) }
        reload()
    }
}

private struct DueRow: View {
    let item: DueOccurrence

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: item.recurring.name)
                    .font(.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text(item.occurrence.date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(.app)))
                    .font(.meta)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            if let amount = item.recurring.amount, let kind = item.recurring.kind {
                MoneyText(money: amount, tone: kind.tone, font: .amountRow)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Record one occurrence with a different amount (e.g. a variable bill).
/// Logic lives in `RecordOccurrenceFormModel`.
private struct RecordOccurrenceFormView: View {
    let item: DueOccurrence

    @Environment(AppContainer.self) private var app
    @State private var model: RecordOccurrenceFormModel?

    var body: some View {
        Group {
            if let model {
                RecordOccurrenceFormContent(model: model)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = RecordOccurrenceFormModel(item: item, service: app.recurring)
        }
    }
}

private struct RecordOccurrenceFormContent: View {
    @Bindable var model: RecordOccurrenceFormModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool

    var body: some View {
        let recurring = model.item.recurring
        NavigationStack {
            Form {
                if let currency = model.currency {
                    Section {
                        AmountField(text: $model.amountText, currency: currency,
                                    tone: recurring.isTransfer ? .transferOut : (recurring.kind?.tone ?? .neutral))
                            .focused($amountFocused)
                    } header: {
                        Text(model.needsReceivedAmount ? "Amount sent" : "Amount")
                    } footer: {
                        Text("Due \(model.item.occurrence.date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(.app))). Only this occurrence changes.")
                    }
                    .surfaceRows()
                }
                if model.loadFailure != nil {
                    Section {
                        ReadFailureLabel("The wallets of this item couldn't be read.")
                    }
                    .surfaceRows()
                }
                if let currency = model.crossCurrencyDestination?.currency {
                    Section("Amount received") {
                        AmountField(text: $model.receivedText, currency: currency, tone: .transferIn)
                    }
                    .surfaceRows()
                }
            }
            .appGroupedStyle()
            .keyboardDismissal()
            .safeAreaInset(edge: .bottom) {
                PrimaryActionBar(title: "Record", isEnabled: model.canSave) {
                    if model.save() { dismiss() }
                }
            }
            .navigationTitle(recurring.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { amountFocused = true }
            .errorAlert(Binding(
                get: { model.failure.map { AlertError($0) } },
                set: { if $0 == nil { model.clearFailure() } }
            ))
        }
        .presentationDetents([.medium, .large])
    }
}
