import SwiftUI
import SwiftData
import FinanceDomain
import FinancePersistence

/// A budget's current period in detail, the spending that counts, and its settings.
struct BudgetDetailView: View {
    let budget: Budget

    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var error: AlertError?

    var body: some View {
        if budget.isDeleted || budget.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            switch Result(catching: { try app.budgets.progress(for: budget, at: .now) }) {
            case .success(let progress):
                summary(progress)
                details(progress)
                spending(in: progress.window)
            case .failure(let error):
                Section {
                    Label((error as? LocalizedError)?.errorDescription ?? String(localized: "Progress unavailable"),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppColor.expense)
                }
            }
            settings
        }
        .navigationTitle(budget.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Edit Budget", systemImage: "pencil") { showingEdit = true }
                    if budget.isArchived {
                        Button("Restore Budget", systemImage: "arrow.uturn.backward") {
                            perform { try app.budgets.restore(budget) }
                        }
                    } else {
                        Button("Archive Budget", systemImage: "archivebox") {
                            perform { try app.budgets.archive(budget) }
                        }
                    }
                    Button("Delete Budget", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            BudgetFormView(mode: .edit(budget))
        }
        .confirmationDialog("Delete \(budget.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Budget", role: .destructive) {
                perform {
                    try app.budgets.delete(budget)
                    dismiss()
                }
            }
        } message: {
            Text("Your transactions are not affected. This can't be undone.")
        }
        .errorAlert($error)
    }

    // MARK: Sections

    private func summary(_ progress: BudgetProgress) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                BudgetStatusLabel(status: progress.status)
                MoneyText(money: progress.remaining, tone: .balance, font: .amountHero)
                Text(progress.remaining.isNegative ? "over budget" : "left to spend")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                BudgetProgressBar(progress: progress)
                    .padding(.top, Spacing.xs)
                Text("Spent \(MoneyFormatter().string(from: progress.spent)) of \(MoneyFormatter().string(from: progress.available))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func details(_ progress: BudgetProgress) -> some View {
        Section {
            LabeledContent("Period", value: BudgetWindowLabel.text(for: progress.window, calendar: app.calendarPolicy))
            LabeledContent("Planned") { MoneyText(money: progress.planned, font: .amountDetail) }
            if budget.rolloverEnabled {
                LabeledContent("Carried over") { MoneyText(money: progress.carriedOver, tone: .balance, font: .amountDetail) }
                LabeledContent("Available") { MoneyText(money: progress.available, font: .amountDetail) }
            }
            LabeledContent("Spent") { MoneyText(money: progress.spent, font: .amountDetail) }
            if let utilization = progress.utilization {
                LabeledContent("Used", value: utilization.formatted(.percent.precision(.fractionLength(0...1))))
            }
            if let allowance = progress.dailyAllowance {
                LabeledContent("Per day for the rest of the period") { MoneyText(money: allowance, font: .amountDetail) }
            }
            if progress.status != .ended {
                LabeledContent("Days left", value: progress.daysLeft.formatted())
            }
        } header: {
            Text("This period")
        } footer: {
            if progress.excludedOtherCurrencyCount > 0 {
                Text("\(progress.excludedOtherCurrencyCount) matching expenses use another currency and are not counted. The app never converts currencies on its own.")
            }
        }
    }

    @ViewBuilder
    private func spending(in window: BudgetWindow) -> some View {
        Section("Spending this period") {
            switch Result(catching: { try app.budgets.spending(for: budget, in: window) }) {
            case .success(let transactions) where transactions.isEmpty:
                Text("Nothing spent in this period yet.")
                    .foregroundStyle(.secondary)
            case .success(let transactions):
                ForEach(transactions) { transaction in
                    NavigationLink(value: transaction) {
                        TransactionRow(transaction: transaction)
                    }
                }
            case .failure:
                Text("Spending couldn't be loaded.")
                    .foregroundStyle(AppColor.expense)
            }
        }
    }

    private var settings: some View {
        Section("Settings") {
            LabeledContent("Repeats", value: budget.period?.displayName ?? "?")
            LabeledContent("Starts", value: budget.startDate.formatted(date: .abbreviated, time: .omitted))
            if let end = budget.endDate {
                LabeledContent("Ends", value: end.formatted(date: .abbreviated, time: .omitted))
            }
            LabeledContent("Categories", value: names(of: (try? app.budgets.categories(of: budget)) ?? []))
            LabeledContent("Wallets", value: budget.appliesToAllWallets
                           ? String(localized: "All wallets")
                           : names(of: (try? app.budgets.wallets(of: budget)) ?? []))
            if budget.period != .custom {
                LabeledContent("Rollover", value: budget.rolloverEnabled ? String(localized: "On") : String(localized: "Off"))
            }
        }
    }

    private func names(of categories: [LedgerCategory]) -> String {
        categories.map(\.name).formatted(.list(type: .and))
    }

    private func names(of wallets: [Wallet]) -> String {
        wallets.map(\.name).formatted(.list(type: .and))
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = AlertError(error) }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query(sort: \Budget.sortOrder) var budgets: [Budget]
    NavigationStack {
        if let budget = budgets.first {
            BudgetDetailView(budget: budget)
                .financeDestinations()
        }
    }
}
