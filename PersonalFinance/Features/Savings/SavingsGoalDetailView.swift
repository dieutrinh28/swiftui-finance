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
                Label((error as? LocalizedError)?.errorDescription ?? String(localized: "Progress unavailable"),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppColor.expense)
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
            }

            Section("History") {
                let entries = goal.contributionsNewestFirst
                if entries.isEmpty {
                    Text("Nothing set aside yet.")
                        .foregroundStyle(.secondary)
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
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    IconBadge(systemName: goal.iconName, tint: PaletteColor(identifier: goal.colorIdentifier).color)
                    if progress.isReached {
                        Label("Goal reached", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.income)
                    } else if progress.isOverdue {
                        Label("Target date passed", systemImage: "exclamationmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.liability)
                    }
                }
                MoneyText(money: progress.saved, font: .amountHero)
                Text("saved of \(MoneyFormatter().string(from: progress.target))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: NSDecimalNumber(decimal: progress.fraction).doubleValue)
                    .tint(progress.isReached ? AppColor.income : ChartPalette.series1)
                    .accessibilityValue(Text(progress.fraction.formatted(.percent.precision(.fractionLength(0)))))
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func plan(_ progress: SavingsProgress) -> some View {
        Section("Plan") {
            LabeledContent("Still needed") { MoneyText(money: progress.remaining, font: .amountDetail) }
            if let date = goal.targetDate {
                LabeledContent("Target date", value: date.formatted(date: .long, time: .omitted))
            }
            if let monthly = progress.suggestedMonthly, let months = progress.monthsLeft {
                LabeledContent("Set aside per month") { MoneyText(money: monthly, font: .amountDetail) }
                Text("For \(months) more month(s) to reach the goal in time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let wallet = try? app.savings.linkedWallet(of: goal) {
                NavigationLink(value: wallet) {
                    LabeledContent("Kept in", value: wallet.name)
                }
                if let allocation = try? app.savings.allocation(of: wallet), allocation.exceedsBalance {
                    Label("Goals linked to \(wallet.name) add up to \(MoneyFormatter().string(from: allocation.allocated)), more than its balance.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(AppColor.liability)
                }
            }
            if let note = goal.note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
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
                    .font(.subheadline.weight(.medium))
                Text([entry.note, entry.date.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let currency, let magnitude = Int64(exactly: entry.amountMinorUnits.magnitude) {
                MoneyText(money: Money(minorUnits: magnitude, currency: currency),
                          tone: entry.isWithdrawal ? .transferOut : .transferIn)
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
