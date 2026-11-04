import SwiftUI

/// Shared column picker content: rendered BOTH in the toolbar menu and in the
/// global View menu (P3.5 "Настроить колонки") so the two can never diverge.
struct ColumnPickerContent: View {
    let session: MapSession
    @AppStorage(ViewSettings.combinedSizeKey) private var combinedSize = true

    var body: some View {
        Toggle(String(localized: "Show Size on Disk"), isOn: $combinedSize)
            .help(Text("On APFS, size on disk can be SMALLER than the file size — transparent compression, sparse files and clones are normal. This is not a bug."))
        Divider()
        ForEach(NodeColumn.pickerCases) { column in
            Toggle(column.menuTitle, isOn: toggle(for: column))
        }
        Divider()
        Button(String(localized: "Reset Columns")) {
            session.columnLayout = .default
            session.sortOrder = ColumnSort.defaults
            NodeColumn.reset()
        }
    }

    private func toggle(for column: NodeColumn) -> Binding<Bool> {
        Binding(
            get: { session.columnLayout.visible.contains(column) },
            set: { visible in
                var layout = session.columnLayout
                if visible {
                    if !layout.visible.contains(column) {
                        // Insert after the currently last "core" column to
                        // keep a sensible order; exact order can be dragged
                        // directly in the table header.
                        layout.visible.append(column)
                    }
                } else {
                    // The name column is the identity of the table — keep it.
                    guard column != .name || layout.visible.count > 1 else { return }
                    layout.visible.removeAll { $0 == column }
                }
                session.columnLayout = layout
            })
    }
}
