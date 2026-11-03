import SwiftUI

/// Export options sheet: scope, columns, paths, layout, values, format.
struct ExportView: View {
    let session: MapSession
    @Binding var format: ExportFormat
    @Environment(\.dismiss) private var dismiss

    @State private var scope: ExportOptions.Scope = .all
    @State private var pathStyle: ExportOptions.PathStyle = .absolute
    @State private var layout: ExportOptions.TableLayout = .flat
    @State private var humanReadable = true
    @State private var includeTotalsRow = true
    @State private var includeThumbnails = false
    @State private var selectedColumns: Set<ExportColumn> = Set(ExportOptions().columns)
    @State private var isRunning = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.menu)

                Picker("Scope", selection: $scope) {
                    Text("Whole map").tag(ExportOptions.Scope.all)
                    Text("Current filtering").tag(ExportOptions.Scope.filtered)
                    Text("Selected items").tag(ExportOptions.Scope.selection)
                }

                Picker("Paths", selection: $pathStyle) {
                    Text("Absolute").tag(ExportOptions.PathStyle.absolute)
                    Text("Relative").tag(ExportOptions.PathStyle.relative)
                }

                Picker("Layout", selection: $layout) {
                    Text("Flat table").tag(ExportOptions.TableLayout.flat)
                    Text("Folder rows (hierarchy)").tag(ExportOptions.TableLayout.folderRows)
                }

                Toggle("Human-readable values (formatted sizes and dates)", isOn: $humanReadable)
                Toggle("Totals row", isOn: $includeTotalsRow)
                if format == .html {
                    Toggle("Embed image thumbnails (first \(HTMLExporter.thumbnailLimit))", isOn: $includeThumbnails)
                }

                VStack(alignment: .leading) {
                    Text("Columns")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(ExportColumn.allCases) { column in
                                Toggle(column.title, isOn: Binding(
                                    get: { selectedColumns.contains(column) },
                                    set: { on in
                                        if on { selectedColumns.insert(column) }
                                        else { selectedColumns.remove(column) }
                                    }))
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .frame(height: 180)
                    .background(.quaternary.opacity(0.15), in: .rect(cornerRadius: 6))
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isRunning ? "Exporting…" : "Export…") {
                    run()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || selectedColumns.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 560)
    }

    private func run() {
        isRunning = true
        errorText = nil
        var options = ExportOptions()
        options.scope = scope
        options.pathStyle = pathStyle
        options.layout = layout
        options.humanReadable = humanReadable
        options.includeTotalsRow = includeTotalsRow
        options.includeThumbnails = includeThumbnails && format == .html
        options.columns = ExportColumn.allCases.filter { selectedColumns.contains($0) }
        let snapshot = session.snapshot
        let filter = session.filter
        let selection = session.selection
        let formatValue = format
        Task {
            defer { isRunning = false }
            guard let snapshot else { return }
            do {
                try await ExportService.runAndSave(snapshot: snapshot, options: options,
                                                   format: formatValue, filter: filter,
                                                   selection: selection)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
