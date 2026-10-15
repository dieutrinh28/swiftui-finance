import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Recurring income, expenses and transfers, with anything due at the top.
struct RecurringListView: View {
    @Environment(AppContainer.self) private var app
    @Query(sort: \RecurringTransaction.sortOrder) private var definitions: [RecurringTransaction]

    @State private var showingNew = false
    @State private var due: Result<Int, any Error> = .success(0)

    var body: some View {
        Group {
            if definitions.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: "No recurring transactions",
                    message: "Add salary, rent, subscriptions or insurance once. When they are due, you confirm them with one tap; nothing is recorded without you."
                ) {
                    Button("Add Recurring", systemImage: "plus") { showingNew = true }
                        .buttonStyle(.appPrimary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    switch due {
                    case .success(let dueCount) where dueCount > 0:
                        Section {
                            NavigationLink(value: AppScreen.due) {
                                InlineLabel("\(dueCount) due to review", systemImage: "bell.badge")
                                    .font(.rowTitle)
                                    .foregroundStyle(AppColor.warning)
                            }
                        }
                        .highlightedRows()
                    case .success:
                        EmptyView()
                    case .failure:
                        Section {
                            ReadFailureLabel("Due items couldn't be checked.")
                        }
                        .highlightedRows()
                    }
                    let active = definitions.filter { !$0.isPaused }
                    let paused = definitions.filter(\.isPaused)
                    if !active.isEmpty {
                        Section("Active") {
                            ForEach(active) { recurring in
                                NavigationLink(value: recurring) { RecurringRow(recurring: recurring) }
                            }
                        }
                        .surfaceRows()
                    }
                    if !paused.isEmpty {
                        Section("Paused") {
                            ForEach(paused) { recurring in
                                NavigationLink(value: recurring) { RecurringRow(recurring: recurring) }
                            }
                        }
                        .surfaceRows()
                    }
                }
                .appGroupedStyle()
            }
        }
        .screenBackground()
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
            due = Result { try app.recurring.dueOccurrences(at: .now).count }
        }
    }
}

struct RecurringRow: View {
    let recurring: RecurringTransaction
    @Environment(AppContainer.self) private var app

    var body: some View {
        HStack(spacing: Spacing.md) {
            let icon = RecurringIcon(recurring, category: Result { try app.recurring.category(of: recurring) })
            IconBadge(systemName: icon.systemName, tint: icon.tint)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: recurring.name)
                    .font(.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(.meta)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: Spacing.sm)
            if let amount = recurring.amount, let kind = recurring.kind {
                MoneyText(money: amount, tone: kind.tone, font: .amountRow)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let frequency = recurring.frequency?.describe(interval: recurring.interval) ?? ""
        if recurring.isPaused { return frequency + " · " + String(localized: "Paused", bundle: .l10n) }
        if case .success(_?) = Result(catching: { try app.recurring.hold(of: recurring) }) {
            return frequency + " · " + String(localized: "On hold", bundle: .l10n)
        }
        guard let schedule = recurring.schedule,
              let next = RecurrenceRules.next(of: schedule, onOrAfter: .now, policy: app.calendarPolicy)
        else { return frequency + " · " + String(localized: "Ended", bundle: .l10n) }
        return frequency + " · " + String(localized: "Next \(next.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.app)))", bundle: .l10n)
    }
}

/// The icon of a recurring item: its category's, a generic one without a category,
/// and a warning sign when the category couldn't be read (never a silent generic icon).
struct RecurringIcon {
    let systemName: String
    let tint: Color

    init(_ recurring: RecurringTransaction, category: Result<LedgerCategory?, any Error>) {
        switch category {
        case .success(let category?):
            systemName = category.iconName
            tint = PaletteColor(identifier: category.colorIdentifier).color
        case .success(nil):
            systemName = recurring.isTransfer ? "arrow.left.arrow.right" : "arrow.triangle.2.circlepath"
            tint = PaletteColor(identifier: "gray").color
        case .failure:
            systemName = "exclamationmark.triangle"
            tint = AppColor.negative
        }
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        RecurringListView()
            .financeDestinations()
    }
}
