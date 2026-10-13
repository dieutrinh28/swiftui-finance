import Foundation
import SwiftUI
import UniformTypeIdentifiers
import FinanceDomain
import FinancePersistence

/// File names, locations and bookkeeping for backups.
enum BackupFiles {
    /// `Date.timeIntervalSince1970` of the last backup the user saved; 0 = never.
    static let lastBackupKey = "lastBackupAt"
    static let safetyCopiesFolder = "Safety Copies"

    /// "Finance Backup 2026-10-13 1015.json"
    static func backupFileName(at date: Date = .now) -> String {
        "Finance Backup \(stamp(date)).json"
    }

    /// "Finance Transactions 2026-10-13.csv"
    static func csvFileName(at date: Date = .now) -> String {
        "Finance Transactions \(stamp(date, time: false)).csv"
    }

    /// `Documents/Safety Copies`, visible in Files › On My iPhone › Finance.
    static func safetyCopiesDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = documents.appending(path: safetyCopiesFolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes the current data before a restore or import changes it.
    /// Returns the file name, or nil when there is nothing to protect.
    static func writeSafetyCopy(
        using service: BackupService,
        before action: String = "restore",
        at date: Date = .now
    ) throws -> String? {
        guard try service.hasUserData() else { return nil }
        let data = try BackupCodec.encode(try service.makeBackup())
        let name = "Before \(action) \(stamp(date)).json"
        try data.write(to: try safetyCopiesDirectory().appending(path: name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// Reads a file picked with `.fileImporter`, which may be outside the sandbox.
    static func readPicked(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private static func stamp(_ date: Date, time: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = time ? "yyyy-MM-dd HHmm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// A backup or CSV file handed to `.fileExporter`.
struct ExportFile: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    let data: Data
    let contentType: UTType
    let fileName: String

    init(data: Data, contentType: UTType, fileName: String) {
        self.data = data
        self.contentType = contentType
        self.fileName = fileName
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
        self.contentType = configuration.contentType
        self.fileName = configuration.file.filename ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
