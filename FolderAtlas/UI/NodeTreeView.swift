import SwiftUI

/// Hierarchical view of the full map as an outline Table: sortable columns,
/// expandable folders with aggregates, native multi-selection.
struct NodeTreeView: View {
    @Bindable var session: MapSession

    var body: some View {
        if let rows = session.treeRows {
            Table(rows,
                  children: \.children,
                  selection: $session.selection,
                  sortOrder: $session.sortOrder,
                  columnCustomization: $session.columnCustomization) {
                NodeTableColumns.all()
            }
            .contextMenu(forSelectionType: Int64.self) { ids in
                if ids.count == 1, let node = session.snapshot?.node(ids.first!) {
                    Button("Open") { session.open(node) }
                    Button("Show in Finder") { session.reveal(node) }
                    Button("Copy Path") { session.copyPath(node) }
                    Button("Compute SHA-256") {
                        session.selection = ids
                        session.computeChecksums(scope: .selection)
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let node = session.snapshot?.node(id) {
                    session.open(node)
                }
            }
        } else {
            ContentUnavailableView("No map yet", systemImage: "map")
        }
    }
}
