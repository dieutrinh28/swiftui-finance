import Foundation
import SwiftData
import FinanceDomain

/// Spreadsheet export of the transaction history (CSV). Read-only.
///
/// One row per transaction, oldest first. Amounts are signed from the point
/// of view of the wallet in the "Wallet" column: income positive, expense
/// negative, a transfer negative (what left the wallet) with the receiving
/// wallet and amount in their own columns.
public struct ExportService {
    public static let transactionColumns = [
        "Date", "Type", "Wallet", "Category", "Amount", "Currency",
        "To wallet", "Amount received", "Received currency", "Note", "Merchant", "ID",
    ]

    private let context: ModelContext
    private let calendar: CalendarPolicy

    public init(context: ModelContext, calendar: CalendarPolicy = CalendarPolicy()) {
        self.context = context
        self.calendar = calendar
    }

    /// - Parameter range: only transactions in `[start, end)`; nil exports everything.
    public func transactionsCSV(in range: DateRange? = nil) throws -> CSVTable {
        var descriptor = FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date), SortDescriptor(\.createdAt)])
        if let range {
            let start = range.start, end = range.end
            descriptor.predicate = #Predicate { $0.date >= start && $0.date < end }
        }
        let transactions = try context.fetch(descriptor)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var table = CSVTable(header: Self.transactionColumns)
        for transaction in transactions {
            guard let kind = transaction.kind else { continue }
            let outgoing = transaction.entries.first { $0.amountMinorUnits < 0 }
            let incoming = transaction.entries.first { $0.amountMinorUnits > 0 }
            let main: LedgerEntry? = kind == .income ? incoming : outgoing
            guard let main, let amount = main.amount else { continue }

            var toWallet = "", received = "", receivedCurrency = ""
            if kind == .transfer, let incoming, let receivedAmount = incoming.amount {
                toWallet = incoming.wallet?.name ?? ""
                received = receivedAmount.plainDecimalString
                receivedCurrency = receivedAmount.currency.code
            }

            table.rows.append([
                .value(formatter.string(from: transaction.date)),
                .value(Self.label(for: kind)),
                .text(main.wallet?.name ?? ""),
                .text(Self.categoryPath(transaction.category)),
                .value(amount.plainDecimalString),
                .value(amount.currency.code),
                .text(toWallet),
                .value(received),
                .value(receivedCurrency),
                .text(transaction.note ?? ""),
                .text(transaction.merchant ?? ""),
                .value(transaction.id.uuidString),
            ])
        }
        return table
    }

    private static func label(for kind: TransactionKind) -> String {
        switch kind {
        case .income: "Income"
        case .expense: "Expense"
        case .transfer: "Transfer"
        }
    }

    /// "Food / Coffee" for a sub-category.
    private static func categoryPath(_ category: LedgerCategory?) -> String {
        guard let category else { return "" }
        if let parent = category.parent { return parent.name + " / " + category.name }
        return category.name
    }
}
