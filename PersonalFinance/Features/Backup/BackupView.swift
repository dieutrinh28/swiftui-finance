import SwiftUI
import UniformTypeIdentifiers
import FinanceDomain
import FinancePersistence
import FinanceFeatures

/// Backup, restore and CSV export.
///
/// - Backup: a complete JSON file saved wherever the user chooses (Files,
///   iCloud Drive, a computer). Nothing leaves the phone otherwise.
/// - Restore: validated first, then a safety copy of the current data is
///   written, then all data is replaced in one transaction (`RestoreFlowModel`).
/// - Spreadsheet: export transactions as CSV, and import a CSV exported by
///   this app (adds transactions only; `ImportFlowModel`).
struct BackupView: View {
    private enum PickedFile {
        case backup
        case csv
    }

    @Environment(AppContainer.self) private var app
    @AppStorage(BackupFiles.lastBackupKey) private var lastBackupAt: Double = 0

    @State private var exportFile: ExportFile?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pickedFile: PickedFile = .backup
    @State private var restoreFlow: RestoreFlowModel?
    @State private var importFlow: ImportFlowModel?
    @State private var error: AlertError?

    var body: some View {
        List {
            backupSection
            restoreSection
            exportSection
        }
        .navigationTitle("Backup & Export")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showingExporter,
            document: exportFile,
            contentType: exportFile?.contentType ?? .json,
            defaultFilename: exportFile?.fileName
        ) { result in
            switch result {
            case .success:
                if exportFile?.contentType == .json { lastBackupAt = Date.now.timeIntervalSince1970 }
            case .failure(let failure):
                error = AlertError(failure)
            }
            exportFile = nil
        }
        // One importer for both kinds of file: SwiftUI supports a single
        // `.fileImporter` per view reliably.
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: pickedFile == .csv ? [.commaSeparatedText, .plainText] : [.json]
        ) { result in
            let data = Result { try BackupFiles.readPicked(try result.get()) }
            switch pickedFile {
            case .backup:
                let flow = makeRestoreFlow()
                switch data {
                case .success(let data): flow.load(data)
                case .failure(let failure): flow.fail(failure)
                }
                restoreFlow = flow
            case .csv:
                let flow = makeImportFlow()
                switch data {
                case .success(let data): flow.load(data)
                case .failure(let failure): flow.fail(failure)
                }
                importFlow = flow
            }
        }
        .sheet(isPresented: Binding(
            get: { (restoreFlow?.isInProgress ?? false) || (importFlow?.isInProgress ?? false) },
            set: { if !$0 { finishFlows() } }
        )) {
            if let restoreFlow {
                RestoreReviewView(flow: restoreFlow) { finishFlows() }
            } else if let importFlow {
                ImportReviewView(flow: importFlow) { finishFlows() }
            }
        }
        .errorAlert($error)
    }

    // MARK: Sections

    private var backupSection: some View {
        Section {
            Button {
                prepareBackup()
            } label: {
                Label("Save Backup…", systemImage: "externaldrive.badge.plus")
            }
            LabeledContent("Last backup", value: lastBackupText)
                .foregroundStyle(lastBackupIsStale ? AppColor.liability : Color.primary)
        } header: {
            Text("Backup")
        } footer: {
            Text("A complete copy of your wallets, transactions, categories, budgets, savings goals and recurring transactions. Save it outside this iPhone, for example in iCloud Drive or on a computer.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                pickedFile = .backup
                showingImporter = true
            } label: {
                Label("Restore from Backup…", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Restore")
        } footer: {
            Text("Replaces all data on this iPhone with the backup. The file is checked first, and a copy of your current data is kept in Files › On My iPhone › Finance › \(BackupFiles.safetyCopiesFolder).")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                prepareCSV()
            } label: {
                Label("Export Transactions (CSV)…", systemImage: "tablecells")
            }
            Button {
                pickedFile = .csv
                showingImporter = true
            } label: {
                Label("Import Transactions (CSV)…", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Spreadsheet (CSV)")
        } footer: {
            Text("Export all transactions for Excel, Numbers or Google Sheets. Import adds transactions from a CSV exported by this app (also after editing it); it never changes or deletes existing ones. A CSV is not a backup: it has no budgets, goals or opening balances.")
        }
    }

    // MARK: Actions

    private func prepareBackup() {
        do {
            let data = try BackupCodec.encode(try app.backup.makeBackup())
            exportFile = ExportFile(data: data, contentType: .json, fileName: BackupFiles.backupFileName())
            showingExporter = true
        } catch {
            self.error = AlertError(error)
        }
    }

    private func prepareCSV() {
        do {
            let text = try app.export.transactionsCSV().render()
            exportFile = ExportFile(data: Data(text.utf8), contentType: .commaSeparatedText,
                                    fileName: BackupFiles.csvFileName())
            showingExporter = true
        } catch {
            self.error = AlertError(error)
        }
    }

    private func makeRestoreFlow() -> RestoreFlowModel {
        let backup = app.backup
        return RestoreFlowModel(
            restore: { try backup.restore($0) },
            makeSafetyCopy: { try BackupFiles.writeSafetyCopy(using: backup) }
        )
    }

    private func makeImportFlow() -> ImportFlowModel {
        let importer = app.importer
        let backup = app.backup
        let parser = TransactionCSVParser(policy: app.calendarPolicy)
        return ImportFlowModel(
            makePlan: { try importer.plan(try parser.parse($0)) },
            commit: { try importer.commit($0, includePossibleDuplicates: $1) },
            makeSafetyCopy: { try BackupFiles.writeSafetyCopy(using: backup, before: "import") }
        )
    }

    /// After a successful restore every pushed screen may show a replaced
    /// record, so navigation starts again from Home. An import only adds.
    private func finishFlows() {
        let restored: Bool
        if case .finished = restoreFlow?.step { restored = true } else { restored = false }
        restoreFlow = nil
        importFlow = nil
        if restored { app.router.reset() }
    }

    // MARK: Display

    private var lastBackupText: String {
        guard lastBackupAt > 0 else { return String(localized: "Never") }
        return Date(timeIntervalSince1970: lastBackupAt).formatted(.relative(presentation: .named))
    }

    private var lastBackupIsStale: Bool {
        lastBackupAt == 0 || Date.now.timeIntervalSince1970 - lastBackupAt > 30 * 86_400
    }
}

/// Confirmation and result of a restore, driven by `RestoreFlowModel.step`.
private struct RestoreReviewView: View {
    let flow: RestoreFlowModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                switch flow.step {
                case .review(let summary):
                    Section {
                        LabeledContent("Created", value: summary.exportedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Wallets", value: "\(summary.wallets)")
                        LabeledContent("Transactions", value: "\(summary.transactions)")
                        LabeledContent("Categories", value: "\(summary.categories)")
                        LabeledContent("Budgets", value: "\(summary.budgets)")
                        LabeledContent("Savings goals", value: "\(summary.savingsGoals)")
                        LabeledContent("Recurring", value: "\(summary.recurring)")
                    } header: {
                        Text("This backup contains")
                    }
                    Section {
                        Label("Everything currently on this iPhone will be replaced. A copy of it is saved first.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppColor.liability)
                        Button("Replace All Data", role: .destructive) { flow.confirm() }
                    }
                case .finished(let summary, let safetyCopy):
                    Section {
                        Label("Restored \(summary.transactions) transactions in \(summary.wallets) wallets.",
                              systemImage: "checkmark.circle")
                        if let safetyCopy {
                            Text("Your previous data was saved as “\(safetyCopy)” in Files › On My iPhone › Finance › \(BackupFiles.safetyCopiesFolder).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "xmark.octagon")
                            .foregroundStyle(AppColor.liability)
                        Text("Nothing was changed.")
                            .foregroundStyle(.secondary)
                    }
                case .idle:
                    EmptyView()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if case .review = flow.step {
                        Button("Cancel", action: onDone)
                    } else {
                        Button("Done", action: onDone)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var title: String {
        switch flow.step {
        case .review: String(localized: "Restore Backup")
        case .finished: String(localized: "Restore Complete")
        case .failed: String(localized: "Can't Restore")
        case .idle: ""
        }
    }
}

/// Preview and result of a CSV import, driven by `ImportFlowModel.step`.
private struct ImportReviewView: View {
    @Bindable var flow: ImportFlowModel
    let onDone: () -> Void

    private static let maxIssuesShown = 50

    var body: some View {
        NavigationStack {
            List {
                switch flow.step {
                case .review(let plan):
                    review(plan)
                case .finished(let result, let safetyCopy):
                    Section {
                        Label("Imported \(result.imported) transaction(s).", systemImage: "checkmark.circle")
                        if result.newWallets > 0 {
                            Text("\(result.newWallets) new wallet(s) were created without an opening balance. Set it in each wallet if needed.")
                                .font(.footnote)
                        }
                        if let safetyCopy {
                            Text("Your data before the import was saved as “\(safetyCopy)” in Files › On My iPhone › Finance › \(BackupFiles.safetyCopiesFolder).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "xmark.octagon")
                            .foregroundStyle(AppColor.liability)
                        Text("Nothing was changed.")
                            .foregroundStyle(.secondary)
                    }
                case .idle:
                    EmptyView()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if case .review = flow.step {
                        Button("Cancel", action: onDone)
                    } else {
                        Button("Done", action: onDone)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func review(_ plan: ImportPlan) -> some View {
        Section {
            LabeledContent("Transactions to add", value: "\(flow.importCount)")
            ForEach(plan.newWallets.indices, id: \.self) { index in
                let wallet = plan.newWallets[index]
                Label("New wallet: \(wallet.name)", systemImage: "wallet.pass")
            }
            ForEach(plan.newCategories.indices, id: \.self) { index in
                let category = plan.newCategories[index]
                Label("New \(category.type == .income ? "income" : "expense") category: \(category.path)", systemImage: "tag")
            }
        } header: {
            Text("This file")
        } footer: {
            if !plan.newWallets.isEmpty {
                Text("New wallets start with no opening balance.")
            }
        }

        if !plan.possibleDuplicates.isEmpty {
            Section {
                Toggle("Import them too", isOn: $flow.includePossibleDuplicates)
            } header: {
                Text("\(plan.possibleDuplicates.count) possible duplicate(s)")
            } footer: {
                Text("Same day, type, wallet and amount as a transaction already in the app. Skipped unless you turn this on.")
            }
        }

        if plan.alreadyImported > 0 || !plan.issues.isEmpty {
            Section {
                if plan.alreadyImported > 0 {
                    Label("\(plan.alreadyImported) already in the app (same ID), skipped.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(plan.issues.prefix(Self.maxIssuesShown).indices, id: \.self) { index in
                    let issue = plan.issues[index]
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Line \(issue.line)").font(.footnote.weight(.semibold))
                        Text(issue.problem.message).font(.footnote)
                    }
                }
                if plan.issues.count > Self.maxIssuesShown {
                    Text("…and \(plan.issues.count - Self.maxIssuesShown) more.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Skipped")
            } footer: {
                if !plan.issues.isEmpty {
                    Text("Rows with problems are left out. Fix them in the file and import it again; rows already imported are skipped.")
                }
            }
        }

        Section {
            Button("Import \(flow.importCount) Transaction(s)") { flow.confirm() }
                .disabled(!flow.canConfirm)
        } footer: {
            Text("Only adds transactions. A copy of your current data is saved first.")
        }
    }

    private var title: String {
        switch flow.step {
        case .review: String(localized: "Import CSV")
        case .finished: String(localized: "Import Complete")
        case .failed: String(localized: "Can't Import")
        case .idle: ""
        }
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        BackupView()
    }
}
