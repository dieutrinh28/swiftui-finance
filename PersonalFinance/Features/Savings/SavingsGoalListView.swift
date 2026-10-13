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
                ContentUnavailableView {
                    Label("No savings goals yet", systemImage: "target")
                } description: {
                    Text("Set money aside for an emergency fund, a trip or a new laptop and track your progress. Goals never change your wallet balances.")
                } actions: {
                    Button("Create Goal") { showingNewGoal = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    goalSection("Active", active)
                    goalSection("Completed", completed)
                    goalSection("Archived", archived)
                }
            }
        }
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
                Text(goal.name).font(.headline)
                Spacer()
            }
            switch Result(catching: { try app.savings.progress(of: goal, at: .now) }) {
            case .success(let progress):
                ProgressView(value: NSDecimalNumber(decimal: progress.fraction).doubleValue)
                    .tint(progress.isReached ? AppColor.income : ChartPalette.series1)
                HStack {
                    Text("\(MoneyFormatter().string(from: progress.saved)) of \(MoneyFormatter().string(from: progress.target))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.footnote.weight(.semibold))
                }
            case .failure:
                Label("Progress unavailable", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(AppColor.expense)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        SavingsGoalListView()
            .financeDestinations()
    }
}
