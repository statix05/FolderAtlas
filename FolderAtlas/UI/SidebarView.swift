import SwiftUI

/// Sidebar: saved maps and per-source scan history.
struct SidebarView: View {
    @Environment(AppLibrary.self) private var library
    let session: MapSession

    @State private var renaming: SnapshotHeader?
    @State private var renameText = ""
    @State private var confirmDelete: SnapshotHeader?

    var body: some View {
        List {
            // Unsaved maps (in-memory drafts): asterisk marker, available
            // until the app quits even after switching to a saved map or
            // closing windows. Temporary SF Symbol "asterisk" — will become
            // the Nerd Font glyph (item 5 / P7).
            Section {
                ForEach(library.drafts) { draft in
                    HStack {
                        Label(draft.displayName, systemImage: "asterisk")
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .help(Text("This map is not saved yet"))
                    .onTapGesture {
                        session.apply(request: MapWindowRequest.existingDraft(draft.id))
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            library.discardDraft(id: draft.id)
                        } label: {
                            Label("Discard Unsaved Map", systemImage: "trash")
                        }
                    }
                }
            } header: {
                if !library.drafts.isEmpty {
                    Text("Unsaved maps")
                }
            }
            Section {
                ForEach(library.savedMaps) { header in
                    mapRow(header)
                }
            } header: {
                Text("Saved maps")
            }
            Section {
                ForEach(library.historyGroups(), id: \.source) { group in
                    DisclosureGroup {
                        ForEach(group.maps) { header in
                            mapRow(header)
                        }
                    } label: {
                        Label(group.source, systemImage: "externaldrive")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } header: {
                Text("Sources & history")
            } footer: {
                Text("Maps open without the original disk — they are metadata snapshots, not backups of file contents.")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Button {
                session.request = nil
                session.displayName = ""
            } label: {
                Label("New Map", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .alert("Rename Map", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renaming {
                    library.rename(id: renaming.id, to: renameText)
                    if session.request?.snapshotID == renaming.id {
                        session.displayName = renameText
                    }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Delete Map", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let confirmDelete { library.delete(id: confirmDelete.id) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("The saved map file will be removed. Original files are not touched.")
        }
    }

    @ViewBuilder
    private func mapRow(_ header: SnapshotHeader) -> some View {
        let isSelected = session.request?.snapshotID == header.id
        HStack {
            Label(header.displayName, systemImage: isSelected ? "map.fill" : "map")
                .lineLimit(1)
            Spacer()
            Text(Fmt.date(header.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            session.apply(request: MapWindowRequest.existing(header.id))
        }
        .contextMenu {
            Button("Open") {
                session.apply(request: MapWindowRequest.existing(header.id))
            }
            Button("Rename…") {
                renaming = header
                renameText = header.displayName
            }
            Button("Delete…", role: .destructive) {
                confirmDelete = header
            }
            Divider()
            Button("Show Map File in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([SnapshotStore.url(for: header.id)])
            }
        }
    }
}
