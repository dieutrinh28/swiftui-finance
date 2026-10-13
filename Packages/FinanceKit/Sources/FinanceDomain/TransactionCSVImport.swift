import Foundation

// MARK: - Reading CSV

extension CSVTable {
    /// Parses RFC 4180 text (comma separated, `"` quoting, CRLF or LF, optional
    /// UTF-8 BOM). Returns each record with the line number it starts on.
    public static func parseRecords(_ text: String) -> [(line: Int, fields: [String])] {
        var records: [(line: Int, fields: [String])] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1
        var recordLine = 1
        var characters = Array(text)
        if characters.first == "\u{FEFF}" { characters.removeFirst() }

        var index = 0
        func endRecord() {
            fields.append(field)
            field = ""
            if !(fields.count == 1 && fields[0].isEmpty) {   // skip blank lines
                records.append((recordLine, fields))
            }
            fields = []
            recordLine = line
        }

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    if character == "\n" || character == "\r\n" { line += 1 }
                    field.append(character)
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case ",":
                    fields.append(field)
                    field = ""
                case "\r\n", "\n", "\r":
                    line += 1
                    endRecord()
                default:
                    field.append(character)
                }
            }
            index += 1
        }
        if !field.isEmpty || !fields.isEmpty { endRecord() }
        return records
    }

    /// Reverses the export's formula guard: `'=SUM(A1)` → `=SUM(A1)`.
    public static func unguard(_ text: String) -> String {
        guard text.count > 1, text.first == "'",
              let second = text.dropFirst().first, "=+-@\t\r".contains(second)
        else { return text }
        return String(text.dropFirst())
    }
}

// MARK: - Import model

/// One transaction read from a CSV row. Amounts are unsigned; the direction
/// comes from `kind` (and, for a transfer, the two wallets).
public struct ImportedTransaction: Equatable, Sendable {
    public let line: Int
    /// The exported transaction's id, when present. Re-importing the same file skips these.
    public let id: UUID?
    public let date: Date
    public let kind: TransactionKind
    public let walletName: String
    public let amount: Money
    /// "Food" or "Food / Coffee"; income and expense only.
    public let categoryPath: String?
    /// Transfers only.
    public let destinationName: String?
    /// Transfers only; nil means "same as amount".
    public let received: Money?
    public let note: String?
    public let merchant: String?

    public init(line: Int, id: UUID?, date: Date, kind: TransactionKind, walletName: String, amount: Money,
                categoryPath: String?, destinationName: String?, received: Money?, note: String?, merchant: String?) {
        self.line = line; self.id = id; self.date = date; self.kind = kind; self.walletName = walletName
        self.amount = amount; self.categoryPath = categoryPath; self.destinationName = destinationName
        self.received = received; self.note = note; self.merchant = merchant
    }
}

/// Why a row can't be imported. The row is skipped; other rows still import.
public enum ImportProblem: Equatable, Sendable {
    case invalidDate(String)
    case invalidType(String)
    case invalidAmount(String)
    case unsupportedCurrency(String)
    case zeroAmount
    case missingWallet
    case missingCategory
    case missingDestination
    case sameWallet
    case archivedWallet(String)
    case archivedCategory(String)
    case walletCurrencyMismatch(wallet: String, currency: String)
    case rejected(LedgerValidationError)
}

extension ImportProblem {
    public var message: String {
        switch self {
        case .invalidDate(let text): "Date “\(text)” is not recognised (use 2026-10-13 or 13/10/2026)."
        case .invalidType(let text): "Type “\(text)” must be Income, Expense or Transfer."
        case .invalidAmount(let text): "Amount “\(text)” is not a number."
        case .unsupportedCurrency(let code): "Currency “\(code)” is not supported."
        case .zeroAmount: "The amount is zero."
        case .missingWallet: "The wallet is empty."
        case .missingCategory: "Income and expenses need a category."
        case .missingDestination: "A transfer needs a “To wallet”."
        case .sameWallet: "A transfer needs two different wallets."
        case .archivedWallet(let name): "Wallet “\(name)” is archived. Restore it first."
        case .archivedCategory(let name): "Category “\(name)” is archived. Restore it first."
        case .walletCurrencyMismatch(let wallet, let currency): "Wallet “\(wallet)” doesn't use \(currency)."
        case .rejected(let error): error.errorDescription ?? "The row was rejected."
        }
    }
}

public struct ImportIssue: Equatable, Sendable {
    public let line: Int
    public let problem: ImportProblem

    public init(line: Int, problem: ImportProblem) {
        self.line = line
        self.problem = problem
    }
}

/// Problems with the whole file; nothing can be imported.
public enum ImportFileError: Error, Equatable, Sendable {
    case notText
    case empty
    case missingColumns([String])
}

extension ImportFileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notText:
            "This file is not a text CSV file."
        case .empty:
            "This file has no transactions."
        case .missingColumns(let columns):
            "This file is missing the column(s) \(columns.joined(separator: ", ")). Import works with CSV files exported by this app."
        }
    }
}

public struct ParsedImport: Equatable, Sendable {
    public var rows: [ImportedTransaction]
    public var issues: [ImportIssue]
}

// MARK: - Parser

/// Reads the transaction CSV this app exports (`ExportService`), including
/// after it was edited and saved in Excel, Numbers or Google Sheets.
///
/// Columns are found by header name, so their order may change. Required:
/// Date, Type, Wallet, Amount, Currency. Amount signs are ignored; the type
/// decides the direction.
public struct TransactionCSVParser: Sendable {
    public static let requiredColumns = ["Date", "Type", "Wallet", "Amount", "Currency"]

    private let policy: CalendarPolicy

    public init(policy: CalendarPolicy = CalendarPolicy()) {
        self.policy = policy
    }

    public func parse(_ data: Data) throws -> ParsedImport {
        guard let text = String(data: data, encoding: .utf8) else { throw ImportFileError.notText }
        let records = CSVTable.parseRecords(text)
        guard let header = records.first else { throw ImportFileError.empty }

        var column: [String: Int] = [:]
        for (index, name) in header.fields.enumerated() {
            column[Self.key(name)] = index
        }
        let missing = Self.requiredColumns.filter { column[Self.key($0)] == nil }
        guard missing.isEmpty else { throw ImportFileError.missingColumns(missing) }

        var result = ParsedImport(rows: [], issues: [])
        for record in records.dropFirst() {
            func value(_ name: String) -> String {
                guard let index = column[Self.key(name)], index < record.fields.count else { return "" }
                return CSVTable.unguard(record.fields[index]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            do {
                result.rows.append(try row(line: record.line, value: value))
            } catch let problem as ImportProblemError {
                result.issues.append(ImportIssue(line: record.line, problem: problem.problem))
            }
        }
        guard !result.rows.isEmpty || !result.issues.isEmpty else { throw ImportFileError.empty }
        return result
    }

    // MARK: Row

    private struct ImportProblemError: Error {
        let problem: ImportProblem
    }

    private func row(line: Int, value: (String) -> String) throws -> ImportedTransaction {
        func fail(_ problem: ImportProblem) -> ImportProblemError { ImportProblemError(problem: problem) }

        let dateText = value("Date")
        guard let date = parseDate(dateText) else { throw fail(.invalidDate(dateText)) }

        let typeText = value("Type")
        guard let kind = Self.kind(typeText) else { throw fail(.invalidType(typeText)) }

        let walletName = value("Wallet")
        guard !walletName.isEmpty else { throw fail(.missingWallet) }

        let amount = try money(value("Amount"), currencyCode: value("Currency"), fail: fail)
        guard !amount.isZero else { throw fail(.zeroAmount) }

        let note = Self.optional(value("Note"))
        let merchant = Self.optional(value("Merchant"))
        let id = UUID(uuidString: value("ID"))

        switch kind {
        case .income, .expense:
            guard let category = Self.optional(value("Category")) else { throw fail(.missingCategory) }
            return ImportedTransaction(line: line, id: id, date: date, kind: kind, walletName: walletName,
                                       amount: amount, categoryPath: category, destinationName: nil,
                                       received: nil, note: note, merchant: merchant)
        case .transfer:
            guard let destination = Self.optional(value("To wallet")) else { throw fail(.missingDestination) }
            guard Self.key(destination) != Self.key(walletName) else { throw fail(.sameWallet) }
            var received: Money?
            let receivedText = value("Amount received")
            if !receivedText.isEmpty {
                let code = Self.optional(value("Received currency")) ?? amount.currency.code
                received = try money(receivedText, currencyCode: code, fail: fail)
                if received?.isZero ?? false { throw fail(.zeroAmount) }
            }
            return ImportedTransaction(line: line, id: id, date: date, kind: .transfer, walletName: walletName,
                                       amount: amount, categoryPath: nil, destinationName: destination,
                                       received: received, note: note, merchant: merchant)
        }
    }

    /// Unsigned money from text the export or a spreadsheet wrote:
    /// "-65000", "65000", "12.5", "1,250.75", and for currencies without
    /// decimals (VND) also "65.000" / "1.250.000" (dot grouping).
    /// Anything ambiguous, such as "65,5", is rejected instead of guessed.
    private func money(
        _ text: String,
        currencyCode: String,
        fail: (ImportProblem) -> ImportProblemError
    ) throws -> Money {
        let code = currencyCode.isEmpty ? CurrencyCatalog.defaultCurrency.code : currencyCode
        guard let currency = try? CurrencyCatalog.definition(for: code) else { throw fail(.unsupportedCurrency(code)) }

        var cleaned = text.replacingOccurrences(of: "\u{2212}", with: "-")
        cleaned.removeAll { $0 == " " || $0 == "\u{00A0}" }
        if cleaned.hasPrefix("-") || cleaned.hasPrefix("+") { cleaned.removeFirst() }

        guard let plain = Self.plainNumber(cleaned, wholeUnitsOnly: currency.minorUnitDigits == 0),
              let decimal = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")),
              let money = try? Money.fromMajorUnits(decimal, currency: currency),
              money.majorUnits == decimal                        // no silent rounding
        else { throw fail(.invalidAmount(text)) }
        return money
    }

    /// "1,250.75" → "1250.75"; "65.000" → "65000" when `wholeUnitsOnly`; nil when ambiguous.
    public static func plainNumber(_ text: String, wholeUnitsOnly: Bool) -> String? {
        func isDigits<S: StringProtocol>(_ part: S) -> Bool {
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
        func isGrouped<S: StringProtocol>(_ part: S, by separator: Character) -> Bool {
            let groups = part.split(separator: separator, omittingEmptySubsequences: false)
            return groups.count >= 2 && (1...3).contains(groups[0].count)
                && groups.allSatisfy { isDigits($0) } && groups.dropFirst().allSatisfy { $0.count == 3 }
        }

        if isDigits(text) { return text }
        if wholeUnitsOnly, isGrouped(text, by: ".") { return text.replacingOccurrences(of: ".", with: "") }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = parts[0]
        guard isDigits(whole) || isGrouped(whole, by: ",") else { return nil }
        if parts.count == 2 { guard isDigits(parts[1]) else { return nil } }
        return text.replacingOccurrences(of: ",", with: "")
    }

    private func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = policy.calendar.timeZone
        formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd",
                       "dd/MM/yyyy HH:mm", "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                // A date without a time is placed at noon, safely inside the day.
                return format.contains("HH") ? date : date.addingTimeInterval(12 * 3_600)
            }
        }
        return nil
    }

    private static func kind(_ text: String) -> TransactionKind? {
        switch key(text) {
        case "income", "thu", "thu nhap": .income
        case "expense", "chi", "chi tieu": .expense
        case "transfer", "chuyen khoan": .transfer
        default: nil
        }
    }

    private static func optional(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    /// Case-, accent- and spacing-insensitive key ("Chuyển khoản" → "chuyen khoan").
    public static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
