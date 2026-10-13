import Foundation

/// A cell in a CSV export.
public enum CSVField: Equatable, Sendable {
    /// Free text typed by the user (names, notes). Protected against formula injection.
    case text(String)
    /// A number or a date we produced ourselves; written as is.
    case value(String)
}

/// RFC 4180 CSV: comma separated, CRLF line endings, fields quoted when needed.
///
/// Spreadsheet apps execute cells that start with `=`, `+`, `-` or `@` as
/// formulas, so user text starting with one of those is prefixed with `'`.
/// Our own numbers are `.value` and keep their minus sign.
public struct CSVTable: Equatable, Sendable {
    public var header: [String]
    public var rows: [[CSVField]]

    public init(header: [String], rows: [[CSVField]] = []) {
        self.header = header
        self.rows = rows
    }

    /// - Parameter byteOrderMark: lets Excel detect UTF-8 (Vietnamese diacritics).
    public func render(byteOrderMark: Bool = true) -> String {
        var lines = [header.map { Self.escape($0) }.joined(separator: ",")]
        for row in rows {
            lines.append(row.map(Self.render).joined(separator: ","))
        }
        return (byteOrderMark ? "\u{FEFF}" : "") + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func render(_ field: CSVField) -> String {
        switch field {
        case .value(let value):
            escape(value)
        case .text(let text):
            if let first = text.first, "=+-@\t\r".contains(first) {
                escape("'" + text)
            } else {
                escape(text)
            }
        }
    }

    public static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension Money {
    /// Plain decimal in major units with a `.` separator and no grouping
    /// (e.g. "-125000" for VND, "12.5" for USD), for spreadsheets.
    public var plainDecimalString: String {
        "\(majorUnits)"
    }
}
