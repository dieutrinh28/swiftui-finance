import Foundation
import Observation
import SwiftData
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Composition root: owns the model container and the application services.
///
/// Write policy: the main context has autosave disabled. Views never mutate
/// models directly; forms keep their own `@State` copies and every change goes
/// through a service that validates, writes and calls `saveOrRollback()` once.
@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer
    let storeLocation: StoreLocation
    let calendarPolicy: CalendarPolicy

    let wallets: WalletService
    let transactions: TransactionService
    let categories: CategoryService
    let budgets: BudgetService
    let reports: ReportService
    let savings: SavingsService
    let recurring: RecurringService
    let backup: BackupService
    let export: ExportService
    let importer: ImportService
    @ObservationIgnored let reminders = ReminderCoordinator()
    /// Selected tab and navigation paths; driven from outside screens (notification taps).
    let router = AppRouter()

    /// Increases after every successful save of the main context. Screens that
    /// derive numbers from many records (dashboard, reports) reload when it changes.
    private(set) var dataVersion = 0
    @ObservationIgnored private var saveObserver: (any NSObjectProtocol)?

    /// Opens (or creates) the store and seeds default categories on first launch.
    convenience init(location: StoreLocation) throws {
        let container = try ModelContainerFactory.makeContainer(at: location)
        container.mainContext.autosaveEnabled = false
        try DefaultCategorySeeder.seedIfNeeded(in: container.mainContext)
        self.init(modelContainer: container, location: location)
    }

    /// Wraps an already-open container (used by previews).
    init(modelContainer: ModelContainer, location: StoreLocation, calendarPolicy: CalendarPolicy = CalendarPolicy()) {
        let context = modelContainer.mainContext
        context.autosaveEnabled = false

        self.modelContainer = modelContainer
        self.storeLocation = location
        self.calendarPolicy = calendarPolicy
        self.wallets = WalletService(context: context)
        self.transactions = TransactionService(context: context, calendar: calendarPolicy)
        self.categories = CategoryService(context: context)
        self.budgets = BudgetService(context: context, calendar: calendarPolicy)
        self.reports = ReportService(context: context)
        self.savings = SavingsService(context: context, calendar: calendarPolicy)
        self.recurring = RecurringService(context: context, calendar: calendarPolicy)
        self.backup = BackupService(context: context)
        self.export = ExportService(context: context, calendar: calendarPolicy)
        self.importer = ImportService(context: context, calendar: calendarPolicy)

        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dataVersion += 1 }
        }
    }
}
