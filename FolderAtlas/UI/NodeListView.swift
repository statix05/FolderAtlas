import SwiftUI

/// Flat table of the filtered map: sortable columns, user-managed column
/// visibility/order via TableColumnCustomization, multi-selection,
/// context menus and double-click opening.
struct NodeListView: View {
    @Bindable var session: MapSession

    var body: some View {
        if session.filtered.isEmpty && session.snapshot != nil {
            ContentUnavailableView.search(text: session.filter.searchText)
        } else {
            table
        }
    }

    private var table: some View {
        Table(session.visibleRows,
              selection: $session.selection,
              sortOrder: $session.sortOrder,
              columnCustomization: $session.columnCustomization) {
            NodeTableColumns.all()
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            selectionMenu(ids)
        } primaryAction: { ids in
            if let id = ids.first, let node = session.snapshot?.node(id) {
                session.open(node)
            }
        }
    }

    @ViewBuilder
    private func selectionMenu(_ ids: Set<Int64>) -> some View {
        if ids.count == 1, let node = session.snapshot?.node(ids.first!) {
            Button("Open") { session.open(node) }
            Button("Show in Finder") { session.reveal(node) }
            Button("Quick Look") {
                session.selection = ids
                session.quickLookSelection()
            }
            Divider()
            Button("Copy Path") { session.copyPath(node) }
            Button("Copy Name") { NSPasteboardHelper.copy(node.name) }
            Divider()
            Button("Compute SHA-256") { session.computeChecksums(scope: .selection) }
            Button("Extract media & EXIF") { session.extractMediaMetadata(scope: .selection) }
        } else {
            Button("Copy Paths") { session.copyPaths(session.selectedNodes) }
            Button("Quick Look") {
                session.selection = ids
                session.quickLookSelection()
            }
            Divider()
            Button("Compute SHA-256") { session.computeChecksums(scope: .selection) }
            Button("Extract media & EXIF") { session.extractMediaMetadata(scope: .selection) }
        }
    }
}

/// The full static column set (split in two halves because the result builder
/// supports at most 10 items per block). Visibility, order and widths are
/// managed by `TableColumnCustomization`. Main-actor isolated because
/// `customizationID` is a MainActor API.
@MainActor
enum NodeTableColumns {

    @TableColumnBuilder<NodeRow, ColumnSort>
    static func all() -> some TableColumnContent<NodeRow, ColumnSort> {
        firstHalf()
        secondHalf()
    }

    @TableColumnBuilder<NodeRow, ColumnSort>
    private static func firstHalf() -> some TableColumnContent<NodeRow, ColumnSort> {
        TableColumn(NodeColumn.name.title, sortUsing: ColumnSort(column: .name, order: .forward)) { row in
            NodeCellView(row: row, column: .name)
        }
        .customizationID(NodeColumn.name.rawValue)
        TableColumn(NodeColumn.kind.title, sortUsing: ColumnSort(column: .kind, order: .forward)) { row in
            NodeCellView(row: row, column: .kind)
        }
        .customizationID(NodeColumn.kind.rawValue)
        TableColumn(NodeColumn.ext.title, sortUsing: ColumnSort(column: .ext, order: .forward)) { row in
            NodeCellView(row: row, column: .ext)
        }
        .customizationID(NodeColumn.ext.rawValue)
        TableColumn(NodeColumn.size.title, sortUsing: ColumnSort(column: .size, order: .forward)) { row in
            NodeCellView(row: row, column: .size)
        }
        .customizationID(NodeColumn.size.rawValue)
        TableColumn(NodeColumn.sizeOnDisk.title, sortUsing: ColumnSort(column: .sizeOnDisk, order: .forward)) { row in
            NodeCellView(row: row, column: .sizeOnDisk)
        }
        .customizationID(NodeColumn.sizeOnDisk.rawValue)
        TableColumn(NodeColumn.created.title, sortUsing: ColumnSort(column: .created, order: .forward)) { row in
            NodeCellView(row: row, column: .created)
        }
        .customizationID(NodeColumn.created.rawValue)
        TableColumn(NodeColumn.modified.title, sortUsing: ColumnSort(column: .modified, order: .forward)) { row in
            NodeCellView(row: row, column: .modified)
        }
        .customizationID(NodeColumn.modified.rawValue)
        TableColumn(NodeColumn.tags.title, sortUsing: ColumnSort(column: .tags, order: .forward)) { row in
            NodeCellView(row: row, column: .tags)
        }
        .customizationID(NodeColumn.tags.rawValue)
        TableColumn(NodeColumn.path.title, sortUsing: ColumnSort(column: .path, order: .forward)) { row in
            NodeCellView(row: row, column: .path)
        }
        .customizationID(NodeColumn.path.rawValue)
    }

    @TableColumnBuilder<NodeRow, ColumnSort>
    private static func secondHalf() -> some TableColumnContent<NodeRow, ColumnSort> {
        TableColumn(NodeColumn.items.title, sortUsing: ColumnSort(column: .items, order: .forward)) { row in
            NodeCellView(row: row, column: .items)
        }
        .customizationID(NodeColumn.items.rawValue)
        TableColumn(NodeColumn.nestedItems.title, sortUsing: ColumnSort(column: .nestedItems, order: .forward)) { row in
            NodeCellView(row: row, column: .nestedItems)
        }
        .customizationID(NodeColumn.nestedItems.rawValue)
        TableColumn(NodeColumn.folderSize.title, sortUsing: ColumnSort(column: .folderSize, order: .forward)) { row in
            NodeCellView(row: row, column: .folderSize)
        }
        .customizationID(NodeColumn.folderSize.rawValue)
        TableColumn(NodeColumn.sha256.title, sortUsing: ColumnSort(column: .sha256, order: .forward)) { row in
            NodeCellView(row: row, column: .sha256)
        }
        .customizationID(NodeColumn.sha256.rawValue)
        TableColumn(NodeColumn.dimensions.title, sortUsing: ColumnSort(column: .dimensions, order: .forward)) { row in
            NodeCellView(row: row, column: .dimensions)
        }
        .customizationID(NodeColumn.dimensions.rawValue)
        TableColumn(NodeColumn.duration.title, sortUsing: ColumnSort(column: .duration, order: .forward)) { row in
            NodeCellView(row: row, column: .duration)
        }
        .customizationID(NodeColumn.duration.rawValue)
        TableColumn(NodeColumn.codec.title, sortUsing: ColumnSort(column: .codec, order: .forward)) { row in
            NodeCellView(row: row, column: .codec)
        }
        .customizationID(NodeColumn.codec.rawValue)
        TableColumn(NodeColumn.flags.title, sortUsing: ColumnSort(column: .flags, order: .forward)) { row in
            NodeCellView(row: row, column: .flags)
        }
        .customizationID(NodeColumn.flags.rawValue)
    }
}

/// A single table cell for a given column.
struct NodeCellView: View {
    let row: NodeRow
    let column: NodeColumn

    private var node: NodeRecord { row.record }

    var body: some View {
        switch column {
        case .name:
            HStack(spacing: 5) {
                Image(systemName: NodeIcons.symbol(for: node))
                    .foregroundStyle(.secondary)
                    .help(NodeFormatters.kindName(node.kind))
                Text(node.displayName)
                    .bold(node.isDirectory)
            }
        case .kind:
            Text(NodeFormatters.kindName(node.kind))
                .foregroundStyle(.secondary)
        case .ext:
            Text(node.ext ?? Fmt.unknown)
                .foregroundStyle(.secondary)
        case .size:
            Text(Fmt.size(node.size))
                .monospacedDigit()
        case .sizeOnDisk:
            Text(Fmt.size(node.allocSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .created:
            Text(Fmt.date(node.created))
                .foregroundStyle(.secondary)
        case .modified:
            Text(Fmt.date(node.modified))
                .foregroundStyle(.secondary)
        case .tags:
            if let tags = node.tags, !tags.isEmpty {
                Text(tags.joined(separator: ", "))
                    .lineLimit(1)
            } else {
                Text(Fmt.unknown).foregroundStyle(.tertiary)
            }
        case .path:
            Text(node.relativePath)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(node.relativePath)
        case .items:
            Text(Fmt.count(node.childCount))
                .monospacedDigit()
        case .nestedItems:
            Text(Fmt.count(node.descendantCount))
                .monospacedDigit()
        case .folderSize:
            Text(Fmt.size(node.dirSize))
                .monospacedDigit()
        case .sha256:
            Text(node.sha256 ?? Fmt.unknown)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        case .dimensions:
            Text(Fmt.dimensions(node.imageInfo?.pixelWidth, node.imageInfo?.pixelHeight))
        case .duration:
            Text(Fmt.seconds(node.mediaInfo?.durationSeconds))
        case .codec:
            Text(node.mediaInfo?.codec ?? Fmt.unknown)
        case .flags:
            HStack(spacing: 3) {
                if node.isHidden {
                    Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
                        .help("Hidden")
                }
                if node.isSymlink {
                    Image(systemName: "arrow.triangle.branch").font(.caption2).foregroundStyle(.secondary)
                        .help("Symlink")
                }
                if node.notDownloaded {
                    Image(systemName: "icloud.slash").font(.caption2).foregroundStyle(.secondary)
                        .help("Not downloaded from iCloud")
                }
                if node.isPackage {
                    Image(systemName: "shippingbox").font(.caption2).foregroundStyle(.secondary)
                        .help("Package")
                }
                if node.error != nil {
                    Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                        .help("Scan error")
                }
            }
        }
    }
}

enum NSPasteboardHelper {
    @MainActor
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
