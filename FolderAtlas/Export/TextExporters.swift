import Foundation

/// CSV / TSV / JSON / Markdown writers.
///
/// Tabular exports protect against formula injection: values that could be
/// interpreted as formulas (=, +, -, @ and control tabs) get a leading
/// apostrophe when written as spreadsheet text.
enum TextExporters {

    // MARK: - Injection guard

    static func guardAgainstFormulas(_ value: String) -> String {
        guard let first = value.first else { return value }
        if "=+-@\t\r".contains(first) {
            return "'" + value
        }
        return value
    }

    // MARK: - CSV / TSV

    static func delimited(rows: [RowBuilder.Row],
                          totals: [ExportCell]?,
                          columns: [ExportColumn],
                          separator: String,
                          bom: Bool) -> Data {
        var lines: [String] = []
        lines.append(columns.map { escape(String($0.title), separator: separator) }.joined(separator: separator))
        for row in rows {
            lines.append(row.cells.map { escape(cellText($0), separator: separator) }.joined(separator: separator))
        }
        if let totals {
            lines.append(totals.map { escape(cellText($0), separator: separator) }.joined(separator: separator))
        }
        var text = lines.joined(separator: "\r\n") + "\r\n"
        if bom { text = "\u{FEFF}" + text }
        return Data(text.utf8)
    }

    private static func cellText(_ cell: ExportCell) -> String {
        guard var text = cell.display else { return "" }
        text = guardAgainstFormulas(text)
        return text
    }

    private static func escape(_ field: String, separator: String) -> String {
        let needsQuoting = field.contains(separator) || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        if needsQuoting {
            return "\"" + field.replacing("\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: - JSON

    static func json(header: SnapshotHeader,
                     columns: [ExportColumn],
                     rows: [RowBuilder.Row],
                     options: ExportOptions) throws -> Data {
        struct JSONValue: Codable {
            enum Kind: Codable {
                case text(String)
                case number(Double)
                case null

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .text(let value): try container.encode(value)
                    case .number(let value): try container.encode(value)
                    case .null: try container.encodeNil()
                    }
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let value = try? container.decode(Double.self) {
                        self = .number(value)
                    } else if let value = try? container.decode(String.self) {
                        self = .text(value)
                    } else {
                        self = .null
                    }
                }
            }

            let value: Kind

            func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
            init(value: Kind) { self.value = value }
        }

        struct JSONPayload: Codable {
            var meta: [String: JSONValue]
            var rows: [[String: JSONValue]]
        }
        var meta: [String: JSONValue] = [
            "map": .init(value: .text(header.displayName)),
            "source": .init(value: .text(header.sourcePath)),
            "created": .init(value: .text(Fmt.iso8601(header.createdAt))),
            "exported": .init(value: .text(Fmt.iso8601(Date()))),
            "scanSettings": .init(value: .text(header.scanSettings.summary)),
            "columns": .init(value: .text(columns.map(\.rawValue).joined(separator: ",")))
        ]
        if options.scope == .filtered && !columns.isEmpty {
            meta["scope"] = JSONValue(value: .text(ExportOptions.Scope.filtered.rawValue))
        }
        var rowsOut: [[String: JSONValue]] = []
        for row in rows {
            var object: [String: JSONValue] = [:]
            for (index, column) in columns.enumerated() {
                let cell = row.cells[index]
                if let number = cell.number, !options.humanReadable {
                    object[column.rawValue] = JSONValue(value: .number(number))
                } else if let display = cell.display {
                    object[column.rawValue] = JSONValue(value: .text(display))
                } else {
                    object[column.rawValue] = JSONValue(value: .null)
                }
            }
            rowsOut.append(object)
        }
        let payload = JSONPayload(meta: meta, rows: rowsOut)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(payload)
    }

    // MARK: - Markdown

    static func markdown(rows: [RowBuilder.Row],
                         totals: [ExportCell]?,
                         columns: [ExportColumn]) -> Data {
        func pipe(_ text: String) -> String {
            text.replacing("|", with: "\\|").replacing("\n", with: "<br>")
        }
        var lines: [String] = []
        lines.append("| " + columns.map { pipe($0.title) }.joined(separator: " | ") + " |")
        lines.append("|" + columns.map { _ in " --- " }.joined(separator: "|") + "|")
        for row in rows {
            lines.append("| " + row.cells.map { pipe(cellText($0)) }.joined(separator: " | ") + " |")
        }
        if let totals {
            lines.append("| " + totals.map { pipe(cellText($0)) }.joined(separator: " | ") + " |")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
