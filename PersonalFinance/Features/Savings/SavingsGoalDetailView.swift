import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

/// A goal's progress, plan and contribution history.
struct SavingsGoalDetailView: View {
    let goal: SavingsGoal

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var entryKind: EntryKind?
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var error: AlertError?

    enum EntryKind: Identifiable {
        case contribution, withdrawal
        var id: Self { self }
    }

    var body: some View {
        if goal.isDeleted || goal.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            switch Result(catching: { try app.savings.progress(of: goal, at: .now) }) {
            case .success(let progress):
                summary(progress)
                plan(progress)
            case .failure(let error):
                Section {
                    ReadFailureLabel("Progress unavailable", error: error)
                }
                .surfaceRows()
            }

            if !goal.isArchived {
                Section {
                    Button {
                        entryKind = .contribution
                    } label: {
                        Label("Add Money", systemImage: "plus.circle")
                    }
                    Button {
                        entryKind = .withdrawal
                    } label: {
                        Label("Take Money Out", systemImage: "minus.circle")
                    }
                } footer: {
                    Text("This records how much of your money is set aside for the goal. It does not move money between wallets or change any balance; record a transfer for that.")
                }
                .surfaceRows()
            }

            Section("History") {
                let entries = goal.contributionsNewestFirst
                if entries.isEmpty {
                    Text("Nothing set aside yet.")
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(entries) { entry in
                        ContributionRow(entry: entry, currency: goal.currency)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            perform { try app.savings.delete(entries[index]) }
                        }
                    }
                }
            }
            .surfaceRows()
        }
        .appGroupedStyle()
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {  // not .secondaryAction: iOS nests that in its own "…" overflow menu
                Menu {
                    Button("Edit Goal", systemImage: "pencil") { showingEdit = true }
                    Button(goal.isCompleted ? "Mark as Not Done" : "Mark as Done",
                           systemImage: goal.isCompleted ? "arrow.uturn.backward" : "checkmark.seal") {
                        perform { try app.savings.setCompleted(goal, !goal.isCompleted) }
                    }
                    Button(goal.isArchived ? "Restore Goal" : "Archive Goal",
                           systemImage: goal.isArchived ? "arrow.uturn.backward" : "archivebox") {
                        perform {
                            if goal.isArchived { try app.savings.restore(goal) } else { try app.savings.archive(goal) }
                        }
                    }
                    Button("Delete Goal", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $entryKind) { kind in
            ContributionFormView(goal: goal, isWithdrawal: kind == .withdrawal)
        }
        .sheet(isPresented: $showingEdit) {
            SavingsGoalFormView(goal: goal)
        }
        .confirmationDialog("Delete \(goal.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Goal", role: .destructive) {
                perform {
                    try app.savings.delete(goal)
                    dismiss()
                }
            }
        } message: {
            Text("The goal and its history are removed. Wallet balances are not affected.")
        }
        .errorAlert($error)
    }

    private func summary(_ progress: SavingsProgress) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    IconBadge(systemName: goal.iconName,
                              tint: PaletteColor(identifier: goal.colorIdentifier).color, size: .large)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: goal.name)
                            .font(.cardTitle)
                            .foregroundStyle(AppColor.textPrimary)
                        if progress.isReached {
                            Label("Goal reached", systemImage: "checkmark.seal.fill")
                                .font(.meta.weight(.semibold))
                                .foregroundStyle(AppColor.positive)
                        } else if progress.isOverdue {
                            Label("Target date passed", systemImage: "exclamationmark.circle")
                                .font(.meta.weight(.semibold))
                                .foregroundStyle(AppColor.warning)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    MoneyText(money: progress.saved, font: .amountHero)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("saved of \(MoneyFormatter().string(from: progress.target))")
                        .font(.label)
                        .foregroundStyle(AppColor.textSecondary)
                }
                SavingsProgressBar(progress: progress)
                if goal.isArchived {
                    NoticeBanner(systemImage: "archivebox",
                                 title: "Archived",
                                 message: "Restore this goal to add or take out money.",
                                 tone: .attention)
                }
            }
            .padding(.vertical, Spacing.sm)
        }
        .highlightedRows()
    }

    private func plan(_ progress: SavingsProgress) -> some View {
        Section("Plan") {
            LabeledContent("Still needed") { MoneyText(money: progress.remaining, font: .amountDetail) }
            if let date = goal.targetDate {
                LabeledContent("Target date", value: date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(.app)))
            }
            if let monthly = progress.suggestedMonthly, let months = progress.monthsLeft {
                LabeledContent("Set aside per month") { MoneyText(money: monthly, font: .amountDetail) }
                Text("For \(months) more month(s) to reach the goal in time.")
                    .font(.meta)
                    .foregroundStyle(AppColor.textSecondary)
            }
            switch Result(catching: { try app.savings.linkedWallet(of: goal) }) {
            case .success(let wallet?):
                NavigationLink(value: wallet) {
                    LabeledContent("Kept in", value: wallet.name)
                }
                switch Result(catching: { try app.savings.allocation(of: wallet) }) {
                case .success(let allocation?) where allocation.exceedsBalance:
                    Label("Goals linked to \(wallet.name) add up to \(MoneyFormatter().string(from: allocation.allocated)), more than its balance.",
                          systemImage: "exclamationmark.triangle")
                        .font(.meta)
                        .foregroundStyle(AppColor.warning)
                case .success:
                    EmptyView()
                case .failure:
                    ReadFailureLabel("The wallet's balance couldn't be checked against its goals.")
                }
            case .success(nil):
                EmptyView()
            case .failure:
                LabeledContent("Kept in") { ReadFailureLabel() }
            }
            if let note = goal.note {
                Text(note).font(.meta).foregroundStyle(AppColor.textSecondary)
            }
        }
        .surfaceRows()
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = AlertError(error) }
    }
}

private struct ContributionRow: View {
    let entry: SavingsContribution
    let currency: CurrencyDefinition?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.isWithdrawal ? "Taken out" : "Added")
                    .font(.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text([entry.note, entry.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.app))].compactMap { $0 }.joined(separator: " · "))
                    .font(.meta)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            if let currency, let magnitude = Int64(exactly: entry.amountMinorUnits.magnitude) {
                MoneyText(money: Money(minorUnits: magnitude, currency: currency),
                          tone: entry.isWithdrawal ? .transferOut : .transferIn, font: .amountRow)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query var goals: [SavingsGoal]
    NavigationStack {
        if let goal = goals.first {
            SavingsGoalDetailView(goal: goal)
                .financeDestinations()
        }
    }
}
