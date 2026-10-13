import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

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
                ContentUnavailableView("Nothing due", systemImage: "checkmark.circle",
                                       description: Text("All recurring transactions are up to date."))
            } else {
                Section {
                    ForEach(due) { item in
                        DueRow(item: item)
                            .swipeActions(edge: .trailing) {
                                Button("Skip") { perform { try app.recurring.skip(item) } }
                                    .tint(.gray)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Record") { perform { try app.recurring.record(item) } }
                                    .tint(ChartPalette.series1)
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
            }
        }
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
            AdjustOccurrenceView(item: item)
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
                Text(item.recurring.name).font(.body.weight(.medium))
                Text(item.occurrence.date.formatted(date: .complete, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let amount = item.recurring.amount, let kind = item.recurring.kind {
                MoneyText(money: amount, tone: kind.tone)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Record one occurrence with a different amount (e.g. a variable bill).
private struct AdjustOccurrenceView: View {
    let item: DueOccurrence

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var error: AlertError?

    var body: some View {
        NavigationStack {
            Form {
                if let amount = item.recurring.amount {
                    AmountField(text: $amountText, currency: amount.currency, tone: item.recurring.kind?.tone ?? .neutral)
                }
            }
            .navigationTitle(item.recurring.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") {
                        guard let currency = item.recurring.amount?.currency else { return }
                        do {
                            try app.recurring.record(item, amount: try AmountInputParser().parse(amountText, currency: currency))
                            dismiss()
                        } catch {
                            self.error = AlertError(error)
                        }
                    }
                }
            }
            .onAppear {
                if let amount = item.recurring.amount { amountText = AmountInputParser().editingText(for: amount) }
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium])
    }
}
