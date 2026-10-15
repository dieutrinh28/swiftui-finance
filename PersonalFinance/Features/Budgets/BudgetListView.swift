import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Budgets tab: every active budget with its progress in the current period.
struct BudgetListView: View {
    @Query(filter: #Predicate<Budget> { $0.archivedAt == nil }, sort: \Budget.sortOrder)
    private var budgets: [Budget]

    @Query(filter: #Predicate<Budget> { $0.archivedAt != nil }, sort: \Budget.sortOrder)
    private var archivedBudgets: [Budget]

    @Environment(AppContainer.self) private var app
    @State private var showingNewBudget = false

    var body: some View {
        NavigationStack(path: app.router.binding(for: .budgets)) {
            Group {
                if budgets.isEmpty && archivedBudgets.isEmpty {
                    EmptyStateView(
                        systemImage: "chart.pie",
                        title: "No budgets yet",
                        message: "A budget plans your spending for one or more categories over a week, a month, a year or custom dates, and shows how much is left."
                    ) {
                        Button("Add Budget", systemImage: "plus") { showingNewBudget = true }
                            .buttonStyle(.appPrimary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        if !budgets.isEmpty {
                            Section {
                                ForEach(budgets) { budget in
                                    NavigationLink(value: budget) {
                                        BudgetRow(budget: budget)
                                    }
                                }
                            } footer: {
                                Text("Each budget measures its own categories. If two budgets share a category, both count that spending.")
                            }
                            .surfaceRows()
                        }
                        if !archivedBudgets.isEmpty {
                            Section("Archived") {
                                ForEach(archivedBudgets) { budget in
                                    NavigationLink(value: budget) {
                                        BudgetRow(budget: budget)
                                    }
                                }
                            }
                            .surfaceRows()
                        }
                    }
                    .appGroupedStyle()
                }
            }
            .screenBackground()
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewBudget = true
                    } label: {
                        Label("Add Budget", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewBudget) {
                BudgetFormView(mode: .create)
            }
            .financeDestinations()
        }
    }
}

/// Name, status, progress bar and spent/remaining for the current period.
struct BudgetRow: View {
    let budget: Budget

    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            switch Result(catching: { try app.budgets.progress(for: budget, at: .now) }) {
            case .success(let progress):
                HStack {
                    Text(budget.name)
                        .font(.cardTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    BudgetStatusLabel(status: progress.status)
                }
                BudgetProgressBar(progress: progress)
                HStack {
                    Text("Spent \(MoneyFormatter().string(from: progress.spent)) of \(MoneyFormatter().string(from: progress.available))")
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    MoneyText(money: progress.remaining, tone: .balance, font: .amountDetail)
                }
                Text("\(budget.period?.displayName ?? "") · \(BudgetWindowLabel.text(for: progress.window, calendar: app.calendarPolicy))")
                    .font(.fine)
                    .foregroundStyle(AppColor.textSecondary)
            case .failure(let error):
                Text(budget.name).font(.cardTitle)
                ReadFailureLabel("Progress unavailable", error: error)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

struct BudgetStatusLabel: View {
    let status: BudgetProgress.Status

    var body: some View {
        Label(status.displayName, systemImage: status.systemImage)
            .font(.fine.weight(.semibold))
            .foregroundStyle(status.color)
    }
}

/// Spent ÷ available as a bar. Full (and red) when over budget.
struct BudgetProgressBar: View {
    let progress: BudgetProgress

    var body: some View {
        MeterBar(fraction: fraction, tint: progress.status.color)
            .accessibilityRepresentation {
                ProgressView(value: fraction)
                    .accessibilityValue(Text(percentText))
            }
    }

    private var fraction: Double {
        guard let utilization = progress.utilization else {
            return progress.spent.isPositive ? 1 : 0
        }
        return min(max(NSDecimalNumber(decimal: utilization).doubleValue, 0), 1)
    }

    private var percentText: String {
        guard let utilization = progress.utilization else { return "" }
        return utilization.formatted(.percent.precision(.fractionLength(0...1)).locale(.app))
    }
}

enum BudgetWindowLabel {
    /// "1 Oct – 31 Oct 2026": the window's first and last (inclusive) day.
    static func text(for window: BudgetWindow, calendar: CalendarPolicy) -> String {
        let lastDay = calendar.calendar.date(byAdding: .day, value: -1, to: window.range.end) ?? window.range.end
        let start = window.range.start.formatted(.dateTime.day().month(.abbreviated).locale(.app))
        let end = lastDay.formatted(.dateTime.day().month(.abbreviated).year().locale(.app))
        return "\(start) – \(end)"
    }
}

#Preview("Budgets", traits: .sampleData) {
    BudgetListView()
}

#Preview("Empty", traits: .emptyStore) {
    BudgetListView()
}
