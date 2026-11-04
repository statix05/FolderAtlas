import AppKit

/// Computes the width needed to fit the longest cell value of a column
/// (Excel-style autofit). Pure measurement — unit-tested; the actual width is
/// applied back on the main thread so large maps never freeze the UI.
@MainActor
enum ColumnFit {

    /// Max fitted width for the given column across the visible rows.
    /// Returns nil when there is nothing to measure.
    static func fittedWidth(for column: NodeColumn, rows: [NodeRecord]) -> CGFloat? {
        guard !rows.isEmpty else { return nil }
        let regular = NSFont.systemFont(ofSize: 12)
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        var maxText: CGFloat = 0
        for record in rows {
            let text: String
            let font: NSFont
            switch column {
            case .name:
                text = record.displayName
                font = record.isDirectory
                    ? .systemFont(ofSize: 13, weight: .semibold)
                    : .systemFont(ofSize: 13)
            case .kind:
                text = NodeFormatters.kindName(record.kind); font = regular
            case .ext:
                text = record.ext ?? Fmt.unknown; font = regular
            case .size:
                text = Fmt.size(record.size); font = mono
            case .sizeOnDisk:
                text = Fmt.size(record.allocSize); font = mono
            case .created:
                text = Fmt.date(record.created); font = regular
            case .modified:
                text = Fmt.date(record.modified); font = regular
            case .tags:
                let tags = record.tags ?? []
                text = tags.isEmpty ? Fmt.unknown : tags.joined(separator: ", ")
                font = regular
            case .path:
                text = record.relativePath; font = regular
            case .items, .nestedItems:
                text = Fmt.count(record.childCount); font = mono
            case .folderSize:
                text = Fmt.size(record.dirSize); font = mono
            case .sha256:
                text = record.sha256 ?? Fmt.unknown
                font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            case .dimensions:
                text = Fmt.dimensions(record.imageInfo?.pixelWidth, record.imageInfo?.pixelHeight)
                font = mono
            case .duration:
                text = Fmt.seconds(record.mediaInfo?.durationSeconds); font = regular
            case .codec:
                text = record.mediaInfo?.codec ?? Fmt.unknown; font = regular
            case .flags:
                // Icons only — fixed intrinsic size, no measurement needed.
                return nil
            }
            maxText = max(maxText, (text as NSString).size(withAttributes: [.font: font]).width)
        }
        // Horizontal padding from horizontalCell/wrap: leading 4 + trailing ~4,
        // plus icon (15) + spacing (5) for the name column.
        let extra: CGFloat = column == .name ? 4 + 15 + 5 + 6 : 10
        return min(900, max(40, ceil(maxText + extra)))
    }
}
