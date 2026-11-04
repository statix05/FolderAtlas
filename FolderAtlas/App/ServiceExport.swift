import Foundation
import AppKit

/// Headless map generation triggered by the Finder Services menu item:
/// scans the folder and writes a ready-to-send XLSX file next to it.
enum ServiceExport {

    static func generateMap(for folder: URL) async -> URL? {
        let config = ScanConfiguration(
            includeHidden: UserDefaults.standard.object(forKey: "scan.includeHidden") as? Bool ?? true,
            includePackageContents: UserDefaults.standard.object(forKey: "scan.includePackages") as? Bool ?? true,
            computeFolderSizes: UserDefaults.standard.object(forKey: "scan.computeFolderSizes") as? Bool ?? true,
            maxDepth: nil)

        guard let output = (try? await ScanEngine.run(root: folder, config: config)) else {
            return nil
        }
        let header = SnapshotHeader(
            displayName: folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent,
            sourcePath: folder.path,
            scanSettings: config,
            fileCount: output.stats.fileCount,
            folderCount: output.stats.folderCount,
            errorCount: output.stats.errorCount,
            totalSize: output.stats.totalSize,
            durationSeconds: output.stats.durationSeconds)
        let snapshot = Snapshot(header: header, nodes: output.nodes)

        var options = ExportOptions()
        options.scope = .all
        options.columns = [.name, .kind, .ext, .size, .sizeOnDisk, .created, .modified, .pathRelative]
        options.pathStyle = .absolute
        options.layout = .folderRows
        options.humanReadable = true
        options.includeTotalsRow = true

        let builder = RowBuilder(snapshot: snapshot, options: options, filter: FilterCriteria(), selection: [])
        let rows = builder.rows()
        let totals = builder.totalsRow(for: rows)
        guard let data = (try? XLSXExporter.export(header: snapshot.header,
                                                   columns: options.columns,
                                                   rows: rows,
                                                   totals: totals,
                                                   options: options)), !data.isEmpty else {
            return nil
        }

        let suffix = String(localized: "Folder Map")
        let baseName = folder.lastPathComponent.isEmpty ? "Folder" : folder.lastPathComponent
        let fileName = baseName + " — " + suffix + ".xlsx"

        // Preferred: next to the folder; fallbacks when the parent is not writable.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            folder.deletingLastPathComponent(),
            home.appending(path: "Desktop", directoryHint: .isDirectory),
            home
        ]
        for directory in candidates {
            let target = directory.appending(path: fileName)
            do {
                try data.write(to: target, options: [.atomic])
                return target
            } catch {
                continue
            }
        }
        return nil
    }

    /// Runs one export per folder and reveals the files in Finder when done.
    static func generateAndReveal(folders: [URL]) async {
        let results = await withTaskGroup(of: URL?.self, returning: [URL].self) { group in
            for folder in folders {
                group.addTask { await generateMap(for: folder) }
            }
            var produced: [URL] = []
            for await result in group {
                if let result { produced.append(result) }
            }
            return produced
        }
        guard !results.isEmpty else { return }
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting(results)
        }
    }
}
