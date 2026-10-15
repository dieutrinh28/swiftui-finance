import Foundation
import Testing
@testable import FinanceDomain

@Suite("CSV reading")
struct CSVReadingTests {
    @Test func quotedFieldsAndLineNumbers() {
        let text = "\u{FEFF}A,B\r\n\"x, y\",\"say \"\"hi\"\"\"\r\n\r\n\"two\nlines\",z\r\nlast,row"
        let records = CSVTable.parseRecords(text)
        #expect(records.count == 4)
        #expect(records[0].fields == ["A", "B"])
        #expect(records[1].fields == ["x, y", "say \"hi\""])
        #expect(records[2].fields == ["two\nlines", "z"])
        #expect(records[2].line == 4)                     // the blank line 3 is skipped
        #expect(records[3].fields == ["last", "row"])
        #expect(records[3].line == 6)
    }

    @Test func exportedTableReadsBack() {
        let table = CSVTable(header: ["Note", "Amount"], rows: [[.text("=1+1"), .value("-5")], [.text("Phở, \"bò\""), .value("12.5")]])
        let records = CSVTable.parseRecords(table.render())
        #expect(records.map(\.fields) == [["Note", "Amount"], ["'=1+1", "-5"], ["Phở, \"bò\"", "12.5"]])
        #expect(CSVTable.unguard(records[1].fields[0]) == "=1+1")
        #expect(CSVTable.unguard("'quoted") == "'quoted")       // a real apostrophe is kept
    }

    @Test func numbersAreReadOnlyWhenUnambiguous() {
        #expect(TransactionCSVParser.plainNumber("65000", wholeUnitsOnly: true) == "65000")
        #expect(TransactionCSVParser.plainNumber("65.000", wholeUnitsOnly: true) == "65000")
        #expect(TransactionCSVParser.plainNumber("1.250.000", wholeUnitsOnly: true) == "1250000")
        #expect(TransactionCSVParser.plainNumber("1,250,000", wholeUnitsOnly: true) == "1250000")
        #expect(TransactionCSVParser.plainNumber("1,250.75", wholeUnitsOnly: false) == "1250.75")
        #expect(TransactionCSVParser.plainNumber("12.5", wholeUnitsOnly: false) == "12.5")
        #expect(TransactionCSVParser.plainNumber("65,5", wholeUnitsOnly: true) == nil)
        #expect(TransactionCSVParser.plainNumber("1.2.3", wholeUnitsOnly: false) == nil)
        #expect(TransactionCSVParser.plainNumber("12a", wholeUnitsOnly: false) == nil)
        #expect(TransactionCSVParser.plainNumber("", wholeUnitsOnly: false) == nil)
    }
}

@Suite("Transaction CSV parser")
struct TransactionCSVParserTests {
    static let policy = CalendarPolicy(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)
    static let header = "Date,Type,Wallet,Category,Amount,Currency,To wallet,Amount received,Received currency,Note,Merchant,ID"

    private func parse(_ lines: [String], header: String = Self.header) throws -> ParsedImport {
        try TransactionCSVParser(policy: Self.policy).parse(Data(([header] + lines).joined(separator: "\r\n").utf8))
    }

    @Test func readsTheExportFormat() throws {
        let id = UUID()
        let result = try parse([
            "2026-10-12 12:30,Expense,Cash,Food,-65000,VND,,,,Lunch,Phở 24,\(id.uuidString)",
            "2026-10-12 08:00,Income,Bank,Salary,30000000,VND,,,,,,",
            "2026-10-11 09:15,Transfer,Bank,,-1000000,VND,Cash,1000000,VND,ATM,,",
        ])
        #expect(result.issues.isEmpty)
        #expect(result.rows.count == 3)

        let lunch = result.rows[0]
        #expect(lunch.line == 2)
        #expect(lunch.id == id)
        #expect(lunch.kind == .expense)
        #expect(lunch.amount == Money(minorUnits: 65_000, currency: .vnd))   // unsigned
        #expect(lunch.categoryPath == "Food")
        #expect(lunch.merchant == "Phở 24")
        #expect(Self.policy.dayKey(for: lunch.date) == DayKey(year: 2026, month: 10, day: 12))

        let transfer = result.rows[2]
        #expect(transfer.kind == .transfer)
        #expect(transfer.destinationName == "Cash")
        #expect(transfer.received == Money(minorUnits: 1_000_000, currency: .vnd))
        #expect(transfer.categoryPath == nil)
    }

    @Test func toleratesSpreadsheetEdits() throws {
        // Columns reordered and trimmed, Vietnamese type names, d/m/y dates, grouped VND.
        let result = try parse([
            "\"65.000\",chi,  Cash ,13/10/2026,Ăn uống,VND",
            "\"1,500,000\",Thu nhập,Bank,13/10/2026 18:45,Lương,VND",
        ], header: "Amount,Type,Wallet,Date,Category,Currency")
        #expect(result.issues.isEmpty)
        #expect(result.rows.map(\.kind) == [.expense, .income])
        #expect(result.rows[0].amount.minorUnits == 65_000)
        #expect(result.rows[0].walletName == "Cash")
        #expect(result.rows[1].amount.minorUnits == 1_500_000)
        // A date without a time is placed at noon.
        #expect(Self.policy.calendar.component(.hour, from: result.rows[0].date) == 12)
    }

    /// Type names as the Vietnamese and Japanese UI show them are accepted too.
    @Test(arguments: [
        ("Thu nhập", TransactionKind.income), ("Chi tiêu", .expense),
        ("Chuyển tiền", .transfer), ("Chuyển khoản", .transfer), ("TRANSFER", .transfer),
        ("収入", .income), ("支出", .expense), ("振替", .transfer),
    ])
    func vietnameseTypeNames(name: String, kind: TransactionKind) throws {
        let row = kind == .transfer
            ? "2026-10-12 10:00,\(name),Bank,,-1000,VND,Cash,,,,,"
            : "2026-10-12 10:00,\(name),Cash,\(kind == .income ? "Lương" : "Ăn uống"),1000,VND,,,,,,"
        let result = try parse([row])
        #expect(result.issues.isEmpty)
        #expect(result.rows.first?.kind == kind)
    }

    @Test func badRowsAreReportedNotImported() throws {
        let result = try parse([
            "yesterday,Expense,Cash,Food,-1,VND,,,,,,",
            "2026-10-12 10:00,Gift,Cash,Food,-1,VND,,,,,,",
            "2026-10-12 10:00,Expense,Cash,Food,\"65,5\",VND,,,,,,",
            "2026-10-12 10:00,Expense,Cash,,-1000,VND,,,,,,",
            "2026-10-12 10:00,Expense,Cash,Food,-1000,XYZ,,,,,,",
            "2026-10-12 10:00,Transfer,Cash,,-1000,VND,,,,,,",
            "2026-10-12 10:00,Transfer,Cash,,-1000,VND,cash,,,,,",
            "2026-10-12 10:00,Expense,Cash,Food,0,VND,,,,,,",
            "2026-10-12 10:00,Expense,,Food,-1000,VND,,,,,,",
            "2026-10-12 10:00,Expense,Cash,Food,-1000,VND,,,,,,",
        ])
        #expect(result.rows.count == 1)
        #expect(result.rows[0].line == 11)
        #expect(result.issues.map(\.problem) == [
            .invalidDate("yesterday"),
            .invalidType("Gift"),
            .invalidAmount("65,5"),
            .missingCategory,
            .unsupportedCurrency("XYZ"),
            .missingDestination,
            .sameWallet,
            .zeroAmount,
            .missingWallet,
        ])
        #expect(result.issues.map(\.line) == Array(2...10))
    }

    @Test func wholeFileProblems() {
        let parser = TransactionCSVParser(policy: Self.policy)
        #expect(throws: ImportFileError.missingColumns(["Type", "Currency"])) {
            try parser.parse(Data("Date,Wallet,Amount\n2026-10-12,Cash,1".utf8))
        }
        #expect(throws: ImportFileError.empty) { try parser.parse(Data("\u{FEFF}".utf8)) }
        #expect(throws: ImportFileError.empty) { try parser.parse(Data(Self.header.utf8)) }
        #expect(throws: ImportFileError.notText) { try parser.parse(Data([0xFF, 0xFE, 0x00, 0xD8])) }
    }

    @Test func matchKeyIgnoresCaseAccentsAndSpacing() {
        #expect(TransactionCSVParser.key("  Chuyển   khoản ") == "chuyen khoan")
        #expect(TransactionCSVParser.key("Đi lại") == TransactionCSVParser.key("di lai"))
    }
}
