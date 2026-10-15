import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

/// A recurring definition: schedule, upcoming dates and what has been recorded.
struct RecurringDetailView: View {
    let recurring: RecurringTransaction

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
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
                header
            }
            .highlightedRows()

            Section("Details") {
                LabeledContent("Repeats", value: recurring.frequency?.describe(interval: recurring.interval) ?? "?")
                LabeledContent("First due", value: recurring.startDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.app)))
                if let end = recurring.endDate {
                    LabeledContent("Last due", value: end.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.app)))
                }
                switch Result(catching: { try app.recurring.wallet(of: recurring) }) {
                case .success(let wallet?):
                    NavigationLink(value: wallet) {
                        LabeledContent(recurring.isTransfer ? "From" : "Wallet", value: wallet.name)
                    }
                case .success(nil):
                    EmptyView()
                case .failure:
                    LabeledContent(recurring.isTransfer ? "From" : "Wallet") { ReadFailureLabel() }
                }
                switch Result(catching: { try app.recurring.destinationWallet(of: recurring) }) {
                case .success(let destination?):
                    NavigationLink(value: destination) { LabeledContent("To", value: destination.name) }
                    // convention-ok: C8 converts the item's own amount; no read from the store
                    if let received = try? recurring.receivedAmount(in: destination) {
                        LabeledContent("Received") { MoneyText(money: received, tone: .transfer) }
                    }
                case .success(nil):
                    EmptyView()
                case .failure:
                    LabeledContent("To") { ReadFailureLabel() }
                }
                switch Result(catching: { try app.recurring.category(of: recurring) }) {
                case .success(let category?):
                    LabeledContent("Category") { InlineLabel(verbatim: category.path, systemImage: category.iconName) }
                case .success(nil):
                    EmptyView()
                case .failure:
                    LabeledContent("Category") { ReadFailureLabel() }
                }
                LabeledContent("Reminder", value: reminderText)
                if let note = recurring.note {
                    LabeledContent("Note", value: note)
                }
            }
            .surfaceRows()

            if !recurring.isPaused, let schedule = recurring.schedule {
                Section("Coming up") {
                    // Skipped or recorded early: not "coming up" (same rule as RecurringService.upcoming).
                    let handled = Set(recurring.handledOccurrenceKeys)
                    let upcoming = RecurrenceRules.occurrences(
                        of: schedule, from: .now,
                        through: app.calendarPolicy.calendar.date(byAdding: .year, value: 2, to: .now) ?? .now,
                        policy: app.calendarPolicy, limit: 5 + handled.count
                    )
                    .filter { !handled.contains(RecurrenceRules.occurrenceKey(recurringID: recurring.id, day: $0.day)) }
                    .prefix(5)
                    if upcoming.isEmpty {
                        Text("No upcoming occurrences.").foregroundStyle(AppColor.textSecondary)
                    }
                    ForEach(upcoming, id: \.day) { occurrence in
                        Text(occurrence.date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(.app)))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                }
                .surfaceRows()
            }

            skippedSection

            Section("Recorded") {
                ReadResult(failure: "Recorded transactions couldn't be loaded.") {
                    try app.recurring.recordedTransactions(of: recurring)
                } content: { recorded in
                    if recorded.isEmpty {
                        Text("Nothing recorded yet.").foregroundStyle(AppColor.textSecondary)
                    }
                    ForEach(recorded) { transaction in
                        NavigationLink(value: transaction) { TransactionRow(transaction: transaction) }
                    }
                }
            }
            .surfaceRows()
        }
        .appGroupedStyle()
        .navigationTitle(recurring.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {  // not .secondaryAction: iOS nests that in its own "…" overflow menu
                Menu {
                    Button("Edit Recurring", systemImage: "pencil") { showingEdit = true }
                    Button(recurring.isPaused ? "Resume" : "Pause",
                           systemImage: recurring.isPaused ? "play.circle" : "pause.circle") {
                        perform { try app.recurring.setPaused(recurring, !recurring.isPaused) }
                    }
                    Button("Delete Recurring", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            RecurringFormView(mode: .edit(recurring))
        }
        .confirmationDialog("Delete \(recurring.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Recurring", role: .destructive) {
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

    /// Icon, name, kind and the amount; paused state as a banner.
    private var header: some View {
        let icon = RecurringIcon(recurring, category: Result { try app.recurring.category(of: recurring) })
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                IconBadge(systemName: icon.systemName, tint: icon.tint, size: .large)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: recurring.name)
                        .font(.cardTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(recurring.kind?.displayName ?? "")
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            if let amount = recurring.amount, let kind = recurring.kind {
                MoneyText(money: amount, tone: kind.tone, font: .amountHero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if recurring.isPaused {
                NoticeBanner(systemImage: "pause.circle",
                             title: "Paused",
                             message: "No reminders and nothing becomes due.",
                             tone: .attention)
            }
            switch Result(catching: { try app.recurring.hold(of: recurring) }) {
            case .success(.archivedWallet(let wallet)?):
                NoticeBanner(systemImage: "archivebox",
                             title: "On hold",
                             message: "\(wallet.name) is archived, so nothing becomes due. Restore the wallet or choose another one.",
                             tone: .attention)
            case .success(.archivedCategory(let category)?):
                NoticeBanner(systemImage: "archivebox",
                             title: "On hold",
                             message: "\(category.name) is archived, so nothing becomes due. Restore the category or choose another one.",
                             tone: .attention)
            case .success(nil):
                EmptyView()
            case .failure:
                NoticeBanner(systemImage: "exclamationmark.triangle",
                             title: "Status unavailable",
                             message: "The wallet or category of this item couldn't be read.",
                             tone: .attention)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    /// Skipped occurrences (and ones passed over by a schedule change) can be made due again.
    @ViewBuilder
    private var skippedSection: some View {
        switch Result(catching: { try app.recurring.skippedOccurrences(of: recurring) }) {
        case .success(let skipped) where !skipped.isEmpty:
            Section {
                ForEach(skipped) { occurrence in
                    HStack {
                        Text(occurrence.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Button("Make Due Again") {
                            perform { try app.recurring.reopen(occurrence, of: recurring) }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Skipped")
            } footer: {
                Text("Skipped occurrences, and ones passed over when the schedule changed. Made due again, they appear in Due once their day has come.")
            }
            .surfaceRows()
        case .success:
            EmptyView()
        case .failure:
            Section("Skipped") {
                ReadFailureLabel("Skipped occurrences couldn't be loaded.")
            }
            .surfaceRows()
        }
    }

    private var reminderText: String {
        guard recurring.reminderEnabled else { return String(localized: "Off", bundle: .l10n) }
        let time = app.calendarPolicy.calendar.date(
            byAdding: .minute, value: recurring.reminderMinutes,
            to: app.calendarPolicy.calendar.startOfDay(for: .now)
        ) ?? .now
        return time.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app))
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = AlertError(error) }
    }
}
