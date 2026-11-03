import Foundation
import AppKit
import UniformTypeIdentifiers

/// Orchestrates export runs: builds rows off the main actor, then writes
/// the chosen format to a user-picked destination.
enum ExportService {

    static func data(snapshot: Snapshot,
                     options: ExportOptions,
                     format: ExportFormat,
                     filter: FilterCriteria,
                     selection: Set<Int64>) async throws -> Data {
        let builder = RowBuilder(snapshot: snapshot, options: options, filter: filter, selection: selection)
        let rows = builder.rows()
        let totals = options.includeTotalsRow ? builder.totalsRow(for: rows) : nil
        switch format {
        case .csv:
            return TextExporters.delimited(rows: rows, totals: totals, columns: options.columns,
                                           separator: ",", bom: true)
        case .tsv:
            return TextExporters.delimited(rows: rows, totals: totals, columns: options.columns,
                                           separator: "\t", bom: true)
        case .json:
            return try TextExporters.json(header: snapshot.header, columns: options.columns,
                                          rows: rows, options: options)
        case .markdown:
            return TextExporters.markdown(rows: rows, totals: totals, columns: options.columns)
        case .html:
            return try HTMLExporter.export(header: snapshot.header, columns: options.columns,
                                           rows: rows, totals: totals, options: options)
        case .pdf:
            return PDFExporter.export(header: snapshot.header, columns: options.columns,
                                      rows: rows, totals: totals)
        case .xlsx:
            return try XLSXExporter.export(header: snapshot.header, columns: options.columns,
                                           rows: rows, totals: totals, options: options)
        }
    }

    @MainActor
    static func runAndSave(snapshot: Snapshot,
                           options: ExportOptions,
                           format: ExportFormat,
                           filter: FilterCriteria,
                           selection: Set<Int64>) async throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = sanitizedBaseName(snapshot.header.displayName) + "." + format.fileExtension
        panel.title = String(localized: "Export Map")
        panel.message = String(localized: "Choose where to save the export.")
        let response = await panel.begin()
        guard response == .OK, let destination = panel.url else { return }

        let data = try await data(snapshot: snapshot, options: options, format: format,
                                  filter: filter, selection: selection)
        try data.write(to: destination, options: [.atomic])
    }

    static func sanitizedBaseName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Map" : trimmed
    }
}
