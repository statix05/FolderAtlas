import SwiftUI

/// Flat list of the filtered map, backed by the native NSOutlineView
/// (see NodeTableRepresentable for why SwiftUI Table was replaced).
struct NodeListView: View {
    let session: MapSession

    var body: some View {
        if session.filtered.isEmpty && session.snapshot != nil {
            ContentUnavailableView.search(text: session.filter.searchText)
        } else {
            NodeTableRepresentable(session: session, tree: false)
        }
    }
}

/// Hierarchical view of the full map, backed by the native NSOutlineView.
struct NodeTreeView: View {
    let session: MapSession

    var body: some View {
        if let rows = session.treeRows, !rows.isEmpty {
            NodeTableRepresentable(session: session, tree: true)
        } else if session.snapshot != nil {
            ContentUnavailableView {
                Label("Building map…", systemImage: "map")
            } description: {
                Text("The outline is being prepared.")
            }
        } else {
            ContentUnavailableView("No map yet", systemImage: "map")
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
