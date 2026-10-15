import Foundation
import SwiftData
import UserNotifications
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Local notifications: reminders for recurring transactions and budget alerts.
///
/// Limits (also shown in Settings → Notifications):
/// - iOS decides when notifications are delivered, and the user can turn them off.
/// - The app does not run in the background. Reminders are scheduled ahead of
///   time; due transactions are only recorded when the user opens the app and
///   confirms them.
/// - iOS keeps at most 64 pending notifications, so only the next few
///   occurrences are scheduled; the list is refreshed after every change.
@MainActor
final class ReminderCoordinator {
    nonisolated static let recurringPrefix = "recurring-"
    nonisolated static let budgetPrefix = "budget-"
    nonisolated private static let sentBudgetAlertsKey = "sentBudgetAlerts"
    nonisolated static let budgetAlertsEnabledKey = "budgetAlertsEnabled"

    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks for permission if not decided yet. Returns whether notifications are allowed.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Replaces all recurring reminders with `planned`. Does nothing without permission.
    func reschedule(_ planned: [PlannedReminder]) async {
        guard await isAuthorized() else { return }
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.recurringPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let formatter = MoneyFormatter()
        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(reminder.title) is due today", bundle: .l10n)
            let amount = formatter.string(from: reminder.amount)
            content.body = reminder.kind == .income
                ? String(localized: "Expected income: \(amount). Open the app to record it.", bundle: .l10n)
                : String(localized: "Amount: \(amount). Open the app to record it.", bundle: .l10n)
            content.sound = .default
            content.userInfo = NotificationRoute.due.userInfo

            // convention-ok: C1 notification triggers fire on the device's own clock and calendar
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: Self.recurringPrefix + reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Sends budget alerts for thresholds newly reached in the current period.
    /// Each alert is sent once per budget period (remembered on this device).
    /// `budgets` is every budget, archived ones included: their current-period
    /// keys are kept so restoring one doesn't repeat an alert.
    func checkBudgetAlerts(budgets: [Budget], service: BudgetService) async {
        guard UserDefaults.standard.object(forKey: Self.budgetAlertsEnabledKey) as? Bool ?? true,
              await isAuthorized() else { return }

        var sent = Set(UserDefaults.standard.stringArray(forKey: Self.sentBudgetAlertsKey) ?? [])
        var currentWindows: [UUID: BudgetWindow] = [:]
        var unreadable: Set<UUID> = []
        for budget in budgets {
            let progress: BudgetProgress
            do {
                progress = try service.progress(for: budget, at: .now)
            } catch {
                unreadable.insert(budget.id)
                continue
            }
            currentWindows[budget.id] = progress.window
            guard !budget.isArchived else { continue }
            let thresholds = budget.alertThresholdPercents
            let alreadyAlerted = Set(thresholds.filter {
                sent.contains(BudgetAlertRules.alertKey(budgetID: budget.id, window: progress.window, threshold: $0))
            })
            let reached = BudgetAlertRules.newlyReachedThresholds(
                progress: progress, thresholds: thresholds, alreadyAlerted: alreadyAlerted
            )
            guard let highest = reached.last else { continue }

            let content = UNMutableNotificationContent()
            content.title = highest >= 100
                ? String(localized: "\(budget.name) budget is used up", bundle: .l10n)
                : String(localized: "\(budget.name) budget is \(highest)% used", bundle: .l10n)
            content.body = String(localized: "Spent \(MoneyFormatter().string(from: progress.spent)) of \(MoneyFormatter().string(from: progress.available)).", bundle: .l10n)
            content.sound = .default
            content.userInfo = NotificationRoute.budget(budget.id).userInfo
            let key = BudgetAlertRules.alertKey(budgetID: budget.id, window: progress.window, threshold: highest)
            try? await center.add(UNNotificationRequest(identifier: Self.budgetPrefix + key, content: content, trigger: nil))

            for threshold in reached {
                sent.insert(BudgetAlertRules.alertKey(budgetID: budget.id, window: progress.window, threshold: threshold))
            }
        }
        // Past periods and deleted budgets: no longer needed (the list would only grow).
        sent = BudgetAlertRules.keysToKeep(sent, currentWindows: currentWindows, unreadable: unreadable)
        UserDefaults.standard.set(Array(sent).sorted(), forKey: Self.sentBudgetAlertsKey)
    }

    private func isAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }
}

extension AppContainer {
    /// Refreshes scheduled reminders and budget alerts after data changes.
    func refreshNotifications() async {
        // A read error keeps the reminders already scheduled (rescheduling with
        // nothing would cancel them all); the next save or return to the app tries again.
        do {
            let planned = try recurring.plannedReminders(after: .now)
            await reminders.reschedule(planned)
        } catch {}
        // No budgets read: skip alerts this time rather than forget which were sent.
        do {
            let budgets = try modelContainer.mainContext.fetch(FetchDescriptor<Budget>())
            await reminders.checkBudgetAlerts(budgets: budgets, service: self.budgets)
        } catch {}
    }
}
