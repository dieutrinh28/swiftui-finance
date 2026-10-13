import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Recurring income and expenses, with anything due at the top.
struct RecurringListView: View {
    @Environment(AppContainer.self) private var app
    @Query(sort: \RecurringTransaction.sortOrder) private var definitions: [RecurringTransaction]

    @State private var showingNew = false
    @State private var dueCount = 0

    var body: some View {
        Group {
            if definitions.isEmpty {
                ContentUnavailableView {
                    Label("No recurring transactions", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Add salary, rent, subscriptions or insurance once. When they are due, you confirm them with one tap; nothing is recorded without you.")
                } actions: {
                    Button("Add Recurring") { showingNew = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if dueCount > 0 {
                        Section {
                            NavigationLink(value: AppScreen.due) {
                                Label("\(dueCount) due to review", systemImage: "bell.badge")
                                    .foregroundStyle(AppColor.liability)
                            }
                        }
                    }
                    let active = definitions.filter { !$0.isPaused }
                    let paused = definitions.filter(\.isPaused)
                    if !active.isEmpty {
                        Section("Active") {
                            ForEach(active) { recurring in
                                NavigationLink(value: recurring) { RecurringRow(recurring: recurring) }
                            }
                        }
                    }
                    if !paused.isEmpty {
                        Section("Paused") {
                            ForEach(paused) { recurring in
                                NavigationLink(value: recurring) { RecurringRow(recurring: recurring) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNew = true
                } label: {
                    Label("Add Recurring", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            RecurringFormView(mode: .create)
        }
        .task(id: app.dataVersion) {
            dueCount = (try? app.recurring.dueOccurrences(at: .now).count) ?? 0
        }
    }
}

struct RecurringRow: View {
    let recurring: RecurringTransaction
    @Environment(AppContainer.self) private var app

    var body: some View {
        HStack(spacing: Spacing.md) {
            let category = try? app.recurring.category(of: recurring)
            IconBadge(systemName: category?.iconName ?? "arrow.triangle.2.circlepath",
                      tint: PaletteColor(identifier: category?.colorIdentifier ?? "gray").color)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(recurring.name).font(.body.weight(.medium))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let amount = recurring.amount, let kind = recurring.kind {
                MoneyText(money: amount, tone: kind.tone)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let frequency = recurring.frequency?.describe(interval: recurring.interval) ?? ""
        if recurring.isPaused { return frequency + " · " + String(localized: "Paused") }
        guard let schedule = recurring.schedule,
              let next = RecurrenceRules.next(of: schedule, onOrAfter: .now, policy: app.calendarPolicy)
        else { return frequency + " · " + String(localized: "Ended") }
        return frequency + " · " + String(localized: "Next \(next.date.formatted(date: .abbreviated, time: .omitted))")
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        RecurringListView()
            .financeDestinations()
    }
}
