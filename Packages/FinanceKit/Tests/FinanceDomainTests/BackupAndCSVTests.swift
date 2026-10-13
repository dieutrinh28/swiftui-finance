import Foundation
import Testing
@testable import FinanceDomain

@Suite("Backup format and validation")
struct BackupValidatorTests {
    typealias Doc = BackupDocument
    static let date = Date(timeIntervalSince1970: 1_791_770_400.5)   // exactly representable, so the byte round trip is stable

    /// Two VND wallets, one income category, one expense category,
    /// an income, an expense and a transfer.
    static func sample() -> Doc {
        let cash = UUID(), bank = UUID(), salary = UUID(), food = UUID()
        func wallet(_ id: UUID, _ name: String) -> Doc.WalletRecord {
            .init(id: id, name: name, type: "cash", currencyCode: "VND", openingBalanceMinorUnits: 100_000,
                  iconName: "banknote", colorIdentifier: "green", note: nil, sortOrder: 0,
                  createdAt: date, updatedAt: date, archivedAt: nil)
        }
        func category(_ id: UUID, _ type: String, parent: UUID? = nil) -> Doc.CategoryRecord {
            .init(id: id, name: type, type: type, iconName: "tag", colorIdentifier: "blue", seedKey: nil,
                  parentID: parent, sortOrder: 0, createdAt: date, updatedAt: date, archivedAt: nil)
        }
        func transaction(_ kind: String, category: UUID?, _ entries: [(UUID, Int64)]) -> Doc.TransactionRecord {
            .init(id: UUID(), kind: kind, date: date, dayKey: 20261012, categoryID: category, note: "Bún chả, \"ngon\"",
                  merchant: nil, exchangeRateText: nil, recurringOccurrenceKey: nil, createdAt: date, updatedAt: date,
                  entries: entries.map { .init(id: UUID(), walletID: $0.0, amountMinorUnits: $0.1, currencyCode: "VND") })
        }
        return Doc(
            schemaVersion: "3.0.0",
            exportedAt: date,
            wallets: [wallet(cash, "Cash"), wallet(bank, "Bank")],
            categories: [category(salary, "income"), category(food, "expense")],
            transactions: [
                transaction("income", category: salary, [(bank, 10_000_000)]),
                transaction("expense", category: food, [(cash, -50_000)]),
                transaction("transfer", category: nil, [(bank, -1_000_000), (cash, 1_000_000)]),
            ]
        )
    }

    @Test func validSampleSummarises() throws {
        let summary = try BackupValidator.validate(Self.sample())
        #expect(summary.wallets == 2)
        #expect(summary.categories == 2)
        #expect(summary.transactions == 3)
        #expect(summary.exportedAt == Self.date)
    }

    @Test func codecRoundTripsWithMilliseconds() throws {
        let document = Self.sample()
        let data = try BackupCodec.encode(document)
        let decoded = try BackupCodec.decode(data)
        #expect(decoded.transactions.count == 3)
        #expect(abs(decoded.exportedAt.timeIntervalSince(document.exportedAt)) < 0.001)
        #expect(decoded.transactions[1].note == "Bún chả, \"ngon\"")
        // Encoding the decoded document again gives the same bytes.
        #expect(try BackupCodec.encode(decoded) == data)
    }

    @Test func otherFilesAreRejected() {
        #expect(throws: BackupError.notABackup) { try BackupCodec.decode(Data(#"{"hello":1}"#.utf8)) }
        #expect(throws: BackupError.self) { try BackupCodec.decode(Data("not json".utf8)) }

        let newer = #"{"format":"com.ddtrinh.personalfinance.backup","formatVersion":99}"#
        #expect(throws: BackupError.newerFormat(version: 99)) { try BackupCodec.decode(Data(newer.utf8)) }
    }

    @Test func duplicateIDsAreRejected() {
        var document = Self.sample()
        document.wallets[1].id = document.wallets[0].id
        #expect(throws: BackupError.duplicateID(entity: "wallet")) { try BackupValidator.validate(document) }
    }

    @Test func unknownValuesAreRejected() {
        var document = Self.sample()
        document.wallets[0].currencyCode = "XYZ"
        #expect(throws: BackupError.invalidValue(field: "currency", value: "XYZ")) { try BackupValidator.validate(document) }

        document = Self.sample()
        document.transactions[0].kind = "gift"
        #expect(throws: BackupError.invalidValue(field: "transaction kind", value: "gift")) { try BackupValidator.validate(document) }
    }

    @Test func missingReferencesAreRejected() {
        var document = Self.sample()
        let ghost = UUID()
        document.transactions[1].entries[0].walletID = ghost
        #expect(throws: BackupError.missingReference(entity: "wallet", id: ghost)) { try BackupValidator.validate(document) }

        document = Self.sample()
        document.categories[0].parentID = ghost
        #expect(throws: BackupError.missingReference(entity: "category", id: ghost)) { try BackupValidator.validate(document) }
    }

    @Test func unbalancedTransactionsAreRejected() {
        var document = Self.sample()
        let transferID = document.transactions[2].id
        document.transactions[2].entries[1].amountMinorUnits = 999_999
        #expect(throws: BackupError.invalidTransaction(id: transferID)) { try BackupValidator.validate(document) }

        document = Self.sample()
        let expenseID = document.transactions[1].id
        document.transactions[1].entries[0].amountMinorUnits = 50_000      // positive expense
        #expect(throws: BackupError.invalidTransaction(id: expenseID)) { try BackupValidator.validate(document) }

        document = Self.sample()
        document.transactions[2].entries[1].walletID = document.transactions[2].entries[0].walletID
        #expect(throws: BackupError.invalidTransaction(id: transferID)) { try BackupValidator.validate(document) }
    }

    @Test func categoryCyclesAreRejected() {
        var document = Self.sample()
        document.categories[0].parentID = document.categories[1].id
        document.categories[1].parentID = document.categories[0].id
        #expect(throws: BackupError.categoryCycle) { try BackupValidator.validate(document) }
    }
}

@Suite("CSV")
struct CSVTests {
    @Test func quotesOnlyWhenNeeded() {
        #expect(CSVTable.escape("plain") == "plain")
        #expect(CSVTable.escape("a,b") == "\"a,b\"")
        #expect(CSVTable.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVTable.escape("two\nlines") == "\"two\nlines\"")
    }

    @Test func userTextCannotBecomeAFormula() {
        #expect(CSVTable.render(.text("=SUM(A1)")) == "'=SUM(A1)")
        #expect(CSVTable.render(.text("-5 discount")) == "'-5 discount")
        #expect(CSVTable.render(.value("-50000")) == "-50000")
    }

    @Test func rendersWithBOMAndCRLF() {
        let table = CSVTable(header: ["Date", "Note"], rows: [[.value("2026-10-12"), .text("Phở, bò")]])
        #expect(table.render() == "\u{FEFF}Date,Note\r\n2026-10-12,\"Phở, bò\"\r\n")
        #expect(!table.render(byteOrderMark: false).hasPrefix("\u{FEFF}"))
    }

    @Test func plainDecimals() {
        #expect(Money(minorUnits: -125_000, currency: .vnd).plainDecimalString == "-125000")
        #expect(Money(minorUnits: 1250, currency: .usd).plainDecimalString == "12.5")
    }
}
