import SwiftUI

/// Compare a map with a previously saved map of the same source.
struct DiffView: View {
    @Environment(AppLibrary.self) private var library
    @Bindable var session: MapSession
    @Environment(\.dismiss) private var dismiss

    @State private var oldID: UUID?
    @State private var newID: UUID?
    @State private var running = false
    @State private var shownKind: DiffKind = .added

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report = session.diffReport {
                reportSummary(report)
                Picker("", selection: $shownKind) {
                    Text("Added (\(report.added.count))").tag(DiffKind.added)
                    Text("Removed (\(report.removed.count))").tag(DiffKind.removed)
                    Text("Changed (\(report.changed.count))").tag(DiffKind.changed)
                    Text("Moved (\(report.moved.count))").tag(DiffKind.moved)
                }
                .pickerStyle(.segmented)
                diffTable(report)
            } else {
                pickers
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 780, height: 520)
        .onAppear {
            if let current = session.snapshot?.header.id {
                if newID == nil { newID = current }
                if oldID == nil {
                    oldID = library.savedMaps
                        .filter { $0.sourcePath == session.snapshot?.header.sourcePath && $0.id != current }
                        .first?.id
                }
            }
        }
    }

    @ViewBuilder
    private var pickers: some View {
        let candidates = library.savedMaps.filter {
            $0.sourcePath == session.snapshot?.header.sourcePath || oldID != nil
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("Compare two saved maps of the same source.")
                .foregroundStyle(.secondary)
            HStack {
                Text("Older map")
                Picker("", selection: $oldID) {
                    Text("—").tag(UUID?.none)
                    ForEach(library.savedMaps) { header in
                        Text("\(header.displayName) · \(Fmt.date(header.createdAt))").tag(UUID?.some(header.id))
                    }
                }
                .labelsHidden()
            }
            HStack {
                Text("Newer map")
                Picker("", selection: $newID) {
                    Text("—").tag(UUID?.none)
                    ForEach(library.savedMaps) { header in
                        Text("\(header.displayName) · \(Fmt.date(header.createdAt))").tag(UUID?.some(header.id))
                    }
                }
                .labelsHidden()
            }
            if candidates.isEmpty {
                Text("Save both maps first — comparison needs two snapshots.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(running ? "Comparing…" : "Compare") {
                    guard let oldID, let newID else { return }
                    running = true
                    Task {
                        await session.compare(oldID: oldID, newID: newID)
                        running = false
                    }
                }
                .disabled(oldID == nil || newID == nil || running || oldID == newID)
            }
        }
    }

    private func entries(of report: DiffReport) -> [DiffEntry] {
        switch shownKind {
        case .added: return report.added
        case .removed: return report.removed
        case .changed: return report.changed
        case .moved: return report.moved
        }
    }

    private func reportSummary(_ report: DiffReport) -> some View {
        HStack(spacing: 14) {
            Text("Added \(report.added.count)").foregroundStyle(.green)
            Text("Removed \(report.removed.count)").foregroundStyle(.red)
            Text("Changed \(report.changed.count)").foregroundStyle(.orange)
            Text("Moved \(report.moved.count)").foregroundStyle(.blue)
            Spacer()
            if !report.hasChecksums {
                Text("Move detection used size + creation date (no checksums available).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func diffTable(_ report: DiffReport) -> some View {
        let entries = entries(of: report)
        if entries.isEmpty {
            ContentUnavailableView("No items", systemImage: "checkmark.circle",
                                   description: Text("Nothing in this category."))
        } else {
            Table(entries) {
                TableColumn("Path") { entry in
                    Text(entry.path).lineLimit(1)
                }
                TableColumn("Name") { entry in
                    Text(entry.name).lineLimit(1)
                }
                TableColumn("Size") { entry in
                    Text(Fmt.size((entry.current ?? entry.previous)?.size))
                }
                TableColumn("Delta") { entry in
                    if let delta = entry.sizeDelta, delta != 0 {
                        Text(delta > 0 ? "+\(Fmt.size(delta))" : "−\(Fmt.size(-delta))")
                            .foregroundStyle(delta > 0 ? Color.green : Color.red)
                    } else {
                        Text(Fmt.unknown).foregroundStyle(.tertiary)
                    }
                }
                TableColumn("Confidence") { entry in
                    switch entry.confidence {
                    case .high: Text("High (checksum)").foregroundStyle(.green)
                    case .medium: Text("Medium (dates)").foregroundStyle(.orange)
                    case nil:
                        if entry.kind == .moved {
                            Text("Heuristic").foregroundStyle(.secondary)
                        } else {
                            Text(Fmt.unknown).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

/// Save sheet: name the map before it lands in the library.
struct SaveSheet: View {
    let defaultName: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Map").font(.headline)
            TextField("Name", text: $name)
            Text("Maps are stored in Application Support as metadata snapshots. Original files are never copied or modified.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name.isEmpty ? defaultName : name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear { name = defaultName }
    }
}
