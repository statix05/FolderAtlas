import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv, tsv, json, html, markdown, pdf, xlsx

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .tsv: return "tsv"
        case .json: return "json"
        case .html: return "html"
        case .markdown: return "md"
        case .pdf: return "pdf"
        case .xlsx: return "xlsx"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .tsv: return .tabSeparatedText
        case .json: return .json
        case .html: return .html
        case .markdown: return UTType(filenameExtension: "md") ?? .text
        case .pdf: return .pdf
        case .xlsx: return UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
        }
    }
}

/// One exportable value. `display == nil` means "unknown" (exported as empty
/// cell / JSON null — never as a fabricated zero).
struct ExportCell: Sendable {
    var display: String?
    /// Numeric value kept numeric in JSON and XLSX when the user chose raw values.
    var number: Double?

    init(_ display: String?, number: Double? = nil) {
        self.display = display
        self.number = number
    }

    static func size(_ bytes: Int64?, human: Bool) -> ExportCell {
        guard let bytes else { return ExportCell(nil) }
        return human ? ExportCell(Fmt.size(bytes)) : ExportCell(String(bytes), number: Double(bytes))
    }
}

struct ExportOptions: Sendable, Equatable {
    enum Scope: String, CaseIterable, Sendable {
        case all, filtered, selection
    }

    enum PathStyle: String, CaseIterable, Sendable {
        case absolute, relative
    }

    enum TableLayout: String, CaseIterable, Sendable {
        case flat, folderRows
    }

    var scope: Scope = .all
    var columns: [ExportColumn] = [.name, .kind, .size, .created, .modified, .pathRelative]
    var pathStyle: PathStyle = .absolute
    var layout: TableLayout = .flat
    var humanReadable = true
    var includeThumbnails = false
    var includeTotalsRow = true
}

/// All exportable metadata columns.
enum ExportColumn: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case name, kind, ext
    case pathAbsolute, pathRelative
    case size, sizeOnDisk
    case created, modified
    case tags
    case hidden, symlink, package
    case childCount, descendantCount, folderSize
    case sha256
    case imageWidth, imageHeight, imageFormat, colorModel
    case camera, lens, iso, exposure, aperture, focalLength, takenDate, gps
    case mediaDuration, videoResolution, codec, bitrate, sampleRate, channels
    case cloudStatus, scanError

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return String(localized: "Name")
        case .kind: return String(localized: "Kind")
        case .ext: return String(localized: "Extension")
        case .pathAbsolute: return String(localized: "Path (absolute)")
        case .pathRelative: return String(localized: "Path (relative)")
        case .size: return String(localized: "Size")
        case .sizeOnDisk: return String(localized: "Size on disk")
        case .created: return String(localized: "Created")
        case .modified: return String(localized: "Modified")
        case .tags: return String(localized: "Tags")
        case .hidden: return String(localized: "Hidden")
        case .symlink: return String(localized: "Symlink")
        case .package: return String(localized: "Package")
        case .childCount: return String(localized: "Items")
        case .descendantCount: return String(localized: "Nested items")
        case .folderSize: return String(localized: "Folder size")
        case .sha256: return String(localized: "SHA-256")
        case .imageWidth: return String(localized: "Pixel width")
        case .imageHeight: return String(localized: "Pixel height")
        case .imageFormat: return String(localized: "Image format")
        case .colorModel: return String(localized: "Color model")
        case .camera: return String(localized: "Camera")
        case .lens: return String(localized: "Lens")
        case .iso: return String(localized: "ISO")
        case .exposure: return String(localized: "Exposure")
        case .aperture: return String(localized: "Aperture")
        case .focalLength: return String(localized: "Focal length")
        case .takenDate: return String(localized: "Date taken")
        case .gps: return String(localized: "GPS")
        case .mediaDuration: return String(localized: "Duration")
        case .videoResolution: return String(localized: "Resolution")
        case .codec: return String(localized: "Codec")
        case .bitrate: return String(localized: "Bitrate")
        case .sampleRate: return String(localized: "Sample rate")
        case .channels: return String(localized: "Channels")
        case .cloudStatus: return String(localized: "Cloud status")
        case .scanError: return String(localized: "Scan error")
        }
    }
}

/// Builds export rows from a snapshot according to options and filter.
struct RowBuilder: Sendable {
    let snapshot: Snapshot
    let options: ExportOptions
    let filter: FilterCriteria
    let selection: Set<Int64>

    struct Row: Sendable {
        var cells: [ExportCell]
        var node: NodeRecord
    }

    var sourcePath: String { snapshot.header.sourcePath }

    /// Rows in export order. `folderRows` layout emits a depth-first walk so
    /// every folder row is followed by the rows of its contents.
    func rows() -> [Row] {
        let nodes: [NodeRecord]
        switch options.scope {
        case .all:
            nodes = snapshot.nodes
        case .filtered:
            nodes = snapshot.nodes.filter { filter.matches($0) }
        case .selection:
            nodes = snapshot.nodes.filter { selection.contains($0.id) }
        }
        var ordered: [NodeRecord]
        if options.layout == .folderRows {
            ordered = depthFirst(nodes)
        } else {
            ordered = nodes
        }
        // The scan root itself is not exported as a row.
        ordered = ordered.filter { !$0.relativePath.isEmpty || $0.parentID != nil }
        ordered = ordered.filter { !($0.relativePath.isEmpty && $0.isDirectory) }
        return ordered.map { node in
            Row(cells: options.columns.map { cell($0, node) }, node: node)
        }
    }

    private func depthFirst(_ nodes: [NodeRecord]) -> [NodeRecord] {
        let allowed = Set(nodes.map(\.id))
        var result: [NodeRecord] = []
        func walk(_ id: Int64) {
            guard let node = snapshot.node(id), allowed.contains(id) else { return }
            if !node.relativePath.isEmpty || node.parentID != nil { result.append(node) }
            for child in snapshot.children(of: id) { walk(child.id) }
        }
        // Walk from every top-level node present in the export set.
        for node in nodes where node.parentID == nil || !allowed.contains(node.parentID!) {
            walk(node.id)
        }
        return result
    }

    func cell(_ column: ExportColumn, _ node: NodeRecord) -> ExportCell {
        let human = options.humanReadable
        switch column {
        case .name: return ExportCell(node.name)
        case .kind: return ExportCell(NodeFormatters.kindName(node.kind))
        case .ext: return ExportCell(node.ext)
        case .pathAbsolute:
            if node.relativePath.isEmpty { return ExportCell(sourcePath) }
            return ExportCell(sourcePath + "/" + node.relativePath)
        case .pathRelative: return ExportCell(node.relativePath)
        case .size: return ExportCell.size(node.size, human: human)
        case .sizeOnDisk: return ExportCell.size(node.allocSize, human: human)
        case .created: return ExportCell(node.created.map { _ in human ? Fmt.date(node.created) : Fmt.iso8601(node.created) })
        case .modified: return ExportCell(node.modified.map { _ in human ? Fmt.date(node.modified) : Fmt.iso8601(node.modified) })
        case .tags: return ExportCell(node.tags?.isEmpty == false ? node.tags!.joined(separator: ", ") : nil)
        case .hidden: return ExportCell(node.isHidden ? String(localized: "Yes") : nil)
        case .symlink: return ExportCell(node.isSymlink ? String(localized: "Yes") : nil)
        case .package: return ExportCell(node.isPackage ? String(localized: "Yes") : nil)
        case .childCount: return ExportCell.size(node.childCount, human: human)
        case .descendantCount: return ExportCell.size(node.descendantCount, human: human)
        case .folderSize: return ExportCell.size(node.dirSize, human: human)
        case .sha256: return ExportCell(node.sha256)
        case .imageWidth: return ExportCell.size(node.imageInfo?.pixelWidth.map(Int64.init), human: human)
        case .imageHeight: return ExportCell.size(node.imageInfo?.pixelHeight.map(Int64.init), human: human)
        case .imageFormat: return ExportCell(node.imageInfo?.format)
        case .colorModel: return ExportCell(node.imageInfo?.colorModel)
        case .camera:
            let info = node.imageInfo
            var parts: [String] = []
            if let make = info?.cameraMake { parts.append(make) }
            if let model = info?.cameraModel { parts.append(model) }
            return ExportCell(parts.isEmpty ? nil : parts.joined(separator: " "))
        case .lens: return ExportCell(node.imageInfo?.lensModel)
        case .iso: return ExportCell.size(node.imageInfo?.iso.map(Int64.init), human: human)
        case .exposure: return ExportCell(node.imageInfo?.exposure)
        case .aperture:
            guard let f = node.imageInfo?.fNumber else { return ExportCell(nil) }
            return ExportCell("ƒ/\(String(format: "%.1f", f))", number: f)
        case .focalLength:
            guard let f = node.imageInfo?.focalLength else { return ExportCell(nil) }
            return ExportCell(String(format: "%.0f mm", f), number: f)
        case .takenDate: return ExportCell(node.imageInfo?.takenDate.map { _ in human ? Fmt.date(node.imageInfo!.takenDate) : Fmt.iso8601(node.imageInfo!.takenDate) })
        case .gps: return ExportCell(node.imageInfo?.latitude != nil ? Fmt.coordinates(node.imageInfo?.latitude, node.imageInfo?.longitude) : nil)
        case .mediaDuration:
            return ExportCell(node.mediaInfo?.durationSeconds.map { human ? Fmt.seconds($0) : String(format: "%.2f", $0) })
        case .videoResolution:
            return ExportCell(node.mediaInfo?.pixelWidth != nil
                ? Fmt.dimensions(node.mediaInfo?.pixelWidth, node.mediaInfo?.pixelHeight)
                : nil)
        case .codec: return ExportCell(node.mediaInfo?.codec)
        case .bitrate: return ExportCell.size(node.mediaInfo?.bitrate, human: human)
        case .sampleRate:
            guard let rate = node.mediaInfo?.sampleRate else { return ExportCell(nil) }
            return ExportCell(String(format: "%.0f Hz", rate), number: rate)
        case .channels: return ExportCell.size(node.mediaInfo?.channels.map(Int64.init), human: human)
        case .cloudStatus:
            return ExportCell(node.notDownloaded ? String(localized: "Not downloaded") : nil)
        case .scanError: return ExportCell(node.error)
        }
    }

    /// Totals row (only size-like columns carry sums).
    func totalsRow(for rows: [Row]) -> [ExportCell] {
        var sizeSum: Int64 = 0
        var allocSum: Int64 = 0
        var dirSum: Int64 = 0
        for row in rows {
            if let s = row.node.size { sizeSum += s }
            if let s = row.node.allocSize { allocSum += s }
            if let s = row.node.dirSize { dirSum += s }
        }
        return options.columns.map { column in
            switch column {
            case .name:
                return ExportCell(String(localized: "Total: \(rows.count) items"))
            case .size where options.humanReadable == false: return ExportCell(String(sizeSum), number: Double(sizeSum))
            case .size: return ExportCell(Fmt.size(sizeSum))
            case .sizeOnDisk where options.humanReadable == false: return ExportCell(String(allocSum), number: Double(allocSum))
            case .sizeOnDisk: return ExportCell(Fmt.size(allocSum))
            case .folderSize where options.humanReadable == false: return ExportCell(String(dirSum), number: Double(dirSum))
            case .folderSize: return ExportCell(Fmt.size(dirSum))
            default: return ExportCell(nil)
            }
        }
    }
}

extension ExportCell: Equatable {
    static func == (lhs: ExportCell, rhs: ExportCell) -> Bool {
        lhs.display == rhs.display && lhs.number == rhs.number
    }
}
