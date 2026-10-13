import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

/// A recurring definition: schedule, upcoming dates and what has been recorded.
struct RecurringDetailView: View {
    let recurring: RecurringTransaction

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var error: AlertError?

    var body: some View {
        if recurring.isDeleted || recurring.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(recurring.kind?.displayName ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let amount = recurring.amount, let kind = recurring.kind {
                        MoneyText(money: amount, tone: kind.tone, font: .amountHero)
                    }
                    if recurring.isPaused {
                        Label("Paused: no reminders and nothing becomes due.", systemImage: "pause.circle")
                            .font(.footnote)
                            .foregroundStyle(AppColor.liability)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Section("Details") {
                LabeledContent("Repeats", value: recurring.frequency?.describe(interval: recurring.interval) ?? "?")
                LabeledContent("First due", value: recurring.startDate.formatted(date: .abbreviated, time: .omitted))
                if let end = recurring.endDate {
                    LabeledContent("Last due", value: end.formatted(date: .abbreviated, time: .omitted))
                }
                if let wallet = try? app.recurring.wallet(of: recurring) {
                    NavigationLink(value: wallet) { LabeledContent("Wallet", value: wallet.name) }
                }
                if let category = try? app.recurring.category(of: recurring) {
                    LabeledContent("Category") { Label(category.name, systemImage: category.iconName) }
                }
                LabeledContent("Reminder", value: reminderText)
                if let note = recurring.note {
                    LabeledContent("Note", value: note)
                }
            }

            if !recurring.isPaused, let schedule = recurring.schedule {
                Section("Coming up") {
                    let upcoming = RecurrenceRules.occurrences(
                        of: schedule, from: .now,
                        through: app.calendarPolicy.calendar.date(byAdding: .year, value: 2, to: .now) ?? .now,
                        policy: app.calendarPolicy, limit: 5
                    )
                    if upcoming.isEmpty {
                        Text("No upcoming occurrences.").foregroundStyle(.secondary)
                    }
                    ForEach(upcoming, id: \.day) { occurrence in
                        Text(occurrence.date.formatted(date: .complete, time: .omitted))
                    }
                }
            }

            Section("Recorded") {
                let recorded = (try? app.recurring.recordedTransactions(of: recurring)) ?? []
                if recorded.isEmpty {
                    Text("Nothing recorded yet.").foregroundStyle(.secondary)
                }
                ForEach(recorded) { transaction in
                    NavigationLink(value: transaction) { TransactionRow(transaction: transaction) }
                }
            }
        }
        .navigationTitle(recurring.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { showingEdit = true }
                    Button(recurring.isPaused ? "Resume" : "Pause",
                           systemImage: recurring.isPaused ? "play.circle" : "pause.circle") {
                        perform { try app.recurring.setPaused(recurring, !recurring.isPaused) }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            RecurringFormView(mode: .edit(recurring))
        }
        .confirmationDialog("Delete \(recurring.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                perform {
                    try app.recurring.delete(recurring)
                    dismiss()
                }
            }
        } message: {
            Text("Transactions already recorded from it are kept.")
        }
        .errorAlert($error)
    }

    private var reminderText: String {
        guard recurring.reminderEnabled else { return String(localized: "Off") }
        let time = app.calendarPolicy.calendar.date(
            byAdding: .minute, value: recurring.reminderMinutes,
            to: app.calendarPolicy.calendar.startOfDay(for: .now)
        ) ?? .now
        return time.formatted(date: .omitted, time: .shortened)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = AlertError(error) }
    }
}
