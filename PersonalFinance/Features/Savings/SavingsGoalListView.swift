import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

/// Savings goals: active, completed and archived.
struct SavingsGoalListView: View {
    @Query(sort: \SavingsGoal.sortOrder) private var goals: [SavingsGoal]
    @State private var showingNewGoal = false

    private var active: [SavingsGoal] { goals.filter { !$0.isArchived && !$0.isCompleted } }
    private var completed: [SavingsGoal] { goals.filter { !$0.isArchived && $0.isCompleted } }
    private var archived: [SavingsGoal] { goals.filter(\.isArchived) }

    var body: some View {
        Group {
            if goals.isEmpty {
                EmptyStateView(
                    systemImage: "target",
                    title: "No savings goals yet",
                    message: "Set money aside for an emergency fund, a trip or a new laptop and track your progress. Goals never change your wallet balances."
                ) {
                    Button("Add Goal", systemImage: "plus") { showingNewGoal = true }
                        .buttonStyle(.appPrimary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    goalSection("Active", active)
                    goalSection("Completed", completed)
                    goalSection("Archived", archived)
                }
                .appGroupedStyle()
            }
        }
        .screenBackground()
        .navigationTitle("Savings Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewGoal = true
                } label: {
                    Label("Add Goal", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewGoal) {
            SavingsGoalFormView(goal: nil)
        }
    }

    @ViewBuilder
    private func goalSection(_ title: LocalizedStringKey, _ items: [SavingsGoal]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { goal in
                    NavigationLink(value: goal) {
                        SavingsGoalRow(goal: goal)
                    }
                }
            }
            .surfaceRows()
        }
    }
}

struct SavingsGoalRow: View {
    let goal: SavingsGoal
    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                IconBadge(systemName: goal.iconName, tint: PaletteColor(identifier: goal.colorIdentifier).color)
                Text(verbatim: goal.name)
                    .font(.cardTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
            }
            switch Result(catching: { try app.savings.progress(of: goal, at: .now) }) {
            case .success(let progress):
                SavingsProgressBar(progress: progress)
                HStack {
                    Text("\(MoneyFormatter().string(from: progress.saved)) of \(MoneyFormatter().string(from: progress.target))")
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    Text(progress.fraction.formatted(.percent.precision(.fractionLength(0)).locale(.app)))
                        .font(.meta.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                }
            case .failure:
                ReadFailureLabel("Progress unavailable")
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// Saved ÷ target as a meter; green once reached.
struct SavingsProgressBar: View {
    let progress: SavingsProgress

    var body: some View {
        let fraction = min(max(NSDecimalNumber(decimal: progress.fraction).doubleValue, 0), 1)
        MeterBar(fraction: fraction, tint: progress.isReached ? AppColor.positive : AppColor.accent)
            .accessibilityRepresentation {
                ProgressView(value: fraction)
                    .accessibilityValue(Text(progress.fraction.formatted(.percent.precision(.fractionLength(0)).locale(.app))))
            }
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        SavingsGoalListView()
            .financeDestinations()
    }
}
