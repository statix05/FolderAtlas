import Foundation

/// Table column identities and their sort comparators.
enum NodeColumn: String, CaseIterable, Identifiable, Sendable {
    case name, kind, ext
    case size, sizeOnDisk
    case created, modified
    case tags
    case path
    case items, nestedItems, folderSize
    case sha256
    case dimensions, duration, codec
    case flags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return String(localized: "Name")
        case .kind: return String(localized: "Kind")
        case .ext: return String(localized: "Extension")
        case .size: return String(localized: "Size")
        case .sizeOnDisk: return String(localized: "Size on disk")
        case .created: return String(localized: "Created")
        case .modified: return String(localized: "Modified")
        case .tags: return String(localized: "Tags")
        case .path: return String(localized: "Path")
        case .items: return String(localized: "Items")
        case .nestedItems: return String(localized: "Nested items")
        case .folderSize: return String(localized: "Folder size")
        case .sha256: return String(localized: "SHA-256")
        case .dimensions: return String(localized: "Dimensions")
        case .duration: return String(localized: "Duration")
        case .codec: return String(localized: "Codec")
        case .flags: return String(localized: "Flags")
        }
    }

    private static let sortKey = "columns.sortOrder"

    static func loadSort() -> [ColumnSort] {
        guard let raw = UserDefaults.standard.stringArray(forKey: sortKey) else { return ColumnSort.defaults }
        let parsed = raw.compactMap { token -> ColumnSort? in
            let parts = token.split(separator: ":")
            guard parts.count == 2,
                  let column = NodeColumn.allCases.first(where: { $0.rawValue == String(parts[0]) }),
                  let order = sortOrder(from: String(parts[1])) else { return nil }
            return ColumnSort(column: column, order: order)
        }
        return parsed.isEmpty ? ColumnSort.defaults : parsed
    }

    static func saveSort(_ sorts: [ColumnSort]) {
        UserDefaults.standard.set(sorts.map { "\($0.column.rawValue):\($0.order == .forward ? "forward" : "reverse")" }, forKey: sortKey)
    }

    private static func sortOrder(from raw: String) -> SortOrder? {
        switch raw {
        case "forward": return SortOrder.forward
        case "reverse": return SortOrder.reverse
        default: return nil
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: sortKey)
    }
}

/// Sort comparator for table columns. `nil` metadata sorts before known values.
struct ColumnSort: SortComparator, Hashable, Sendable {
    typealias Compared = NodeRow

    var column: NodeColumn
    var order: SortOrder

    func compare(_ lhs: NodeRow, _ rhs: NodeRow) -> ComparisonResult {
        let result = compareValues(lhs.record, rhs.record)
        if result == .orderedSame { return .orderedSame }
        let flipped: ComparisonResult = result == .orderedAscending ? .orderedDescending : .orderedAscending
        return order == .forward ? result : flipped
    }

    private func compareValues(_ a: NodeRecord, _ b: NodeRecord) -> ComparisonResult {
        switch column {
        case .name:
            return a.name.localizedStandardCompare(b.name)
        case .kind:
            return a.name == b.name ? .orderedSame : (NodeFormatters.kindName(a.kind).localizedStandardCompare(NodeFormatters.kindName(b.kind)))
        case .ext:
            return optionalString(a.ext, b.ext)
        case .size:
            return optionalNumber(a.size, b.size)
        case .sizeOnDisk:
            return optionalNumber(a.allocSize, b.allocSize)
        case .created:
            return optionalDate(a.created, b.created)
        case .modified:
            return optionalDate(a.modified, b.modified)
        case .tags:
            return (a.tags ?? []).joined(separator: ", ").localizedStandardCompare((b.tags ?? []).joined(separator: ", "))
        case .path:
            return a.relativePath.localizedStandardCompare(b.relativePath)
        case .items:
            return optionalNumber(a.childCount, b.childCount)
        case .nestedItems:
            return optionalNumber(a.descendantCount, b.descendantCount)
        case .folderSize:
            return optionalNumber(a.dirSize, b.dirSize)
        case .sha256:
            return optionalString(a.sha256, b.sha256)
        case .dimensions:
            let left = (a.imageInfo?.pixelWidth ?? 0) * (a.imageInfo?.pixelHeight ?? 0)
            let right = (b.imageInfo?.pixelWidth ?? 0) * (b.imageInfo?.pixelHeight ?? 0)
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case .duration:
            return optionalDouble(a.mediaInfo?.durationSeconds, b.mediaInfo?.durationSeconds)
        case .codec:
            return optionalString(a.mediaInfo?.codec, b.mediaInfo?.codec)
        case .flags:
            let left = (a.isHidden ? 4 : 0) + (a.isSymlink ? 2 : 0) + (a.notDownloaded ? 1 : 0)
            let right = (b.isHidden ? 4 : 0) + (b.isSymlink ? 2 : 0) + (b.notDownloaded ? 1 : 0)
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        }
    }

    private func optionalString(_ a: String?, _ b: String?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case (let x?, let y?): return x.localizedStandardCompare(y)
        }
    }

    private func optionalNumber(_ a: Int64?, _ b: Int64?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case (let x?, let y?): return x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
        }
    }

    private func optionalDouble(_ a: Double?, _ b: Double?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case (let x?, let y?): return x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
        }
    }

    private func optionalDate(_ a: Date?, _ b: Date?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case (let x?, let y?): return x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
        }
    }

    static let defaults: [ColumnSort] = [ColumnSort(column: .name, order: .forward)]
}

/// Recursive row type for the outline (tree) table — removed in favour of
/// `NodeRow.children`.

/// SF Symbols for node kinds — only real system symbol names.
enum NodeIcons {
    static func symbol(for node: NodeRecord) -> String {
        switch node.kind {
        case .folder: return "folder"
        case .package: return "shippingbox"
        case .symlink: return "arrow.triangle.branch"
        case .file:
            if node.notDownloaded { return "icloud.slash" }
            switch node.ext {
            case "jpg", "jpeg", "png", "gif", "heic", "tiff", "webp", "bmp", "svg": return "photo"
            case "mp4", "mov", "mkv", "avi", "m4v", "webm": return "video"
            case "mp3", "wav", "aac", "flac", "m4a", "ogg": return "waveform"
            case "app": return "shippingbox"
            default: return "doc"
            }
        }
    }
}
