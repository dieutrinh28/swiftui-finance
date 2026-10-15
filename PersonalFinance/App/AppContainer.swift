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
    /// The language the app is shown in; switchable in More › Language.
    let language: LanguageSettings

    /// Increases after every successful save of the main context. Screens that
    /// derive numbers from many records (dashboard, reports) reload when it changes.
    private(set) var dataVersion = 0
    @ObservationIgnored private var saveObserver: (any NSObjectProtocol)?

    /// Opens (or creates) the store and seeds default categories on first launch.
    convenience init(location: StoreLocation) throws {
        let container = try ModelContainerFactory.makeContainer(at: location)
        container.mainContext.autosaveEnabled = false
        // Built-in categories follow the language the app is shown in
        // (device language, the per-app language in iOS Settings, or the
        // choice in More › Language). Categories the user renamed are never touched.
        let language = LanguageSettings()
        let seedLanguage = SeedLanguage(localization: language.effectiveCode)
        try DefaultCategorySeeder.seedIfNeeded(in: container.mainContext, language: seedLanguage)
        try DefaultCategorySeeder.localizeUntouched(in: container.mainContext, to: seedLanguage)
        self.init(modelContainer: container, location: location, language: language)
    }

    /// Wraps an already-open container (used by previews).
    init(
        modelContainer: ModelContainer,
        location: StoreLocation,
        calendarPolicy: CalendarPolicy = CalendarPolicy(),
        language: LanguageSettings? = nil
    ) {
        let context = modelContainer.mainContext
        context.autosaveEnabled = false

        self.language = language ?? LanguageSettings()
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

    /// Switches the app's language now: texts, built-in category names (if
    /// the user never renamed them) and, through the next refresh, reminders.
    func setLanguage(_ choice: AppLanguage) {
        language.select(choice)
        do {
            try DefaultCategorySeeder.localizeUntouched(
                in: modelContainer.mainContext,
                to: SeedLanguage(localization: language.effectiveCode)
            )
        } catch {
            // Names stay as they are; the next launch tries again. Nothing else depends on them.
        }
    }
}
