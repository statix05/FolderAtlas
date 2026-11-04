import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Root of every map window: sidebar, table/tree content, inspector,
/// toolbar, status bar, sheets and all system integrations.
struct MapWindowRoot: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppLibrary.self) private var library
    @Binding var request: MapWindowRequest?

    /// Set after the first default window decides about auto-opening the
    /// most recent saved map (only the cold-start window does this).
    private static var autoOpenHandled = false

    @State private var session = MapSession()
    @State private var showExport = false
    @State private var showFilter = false
    @State private var showSaveSheet = false
    /// Combine «Size» and «Size on disk» into one slash column (owner option).
    @AppStorage(ViewSettings.combinedSizeKey) private var combinedSize = true
    @State private var showImporter = false
    @State private var pendingFormat: ExportFormat = .csv

    var body: some View {
        NavigationSplitView {
            SidebarView(session: session)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230)
        } detail: {
            detail
        }
        .inspector(isPresented: $session.inspectorVisible) {
            InspectorView(session: session)
                .inspectorColumnWidth(min: 240, ideal: 300)
        }
        .searchable(text: $session.filter.searchText, placement: .toolbar,
                    prompt: Text("Search names and paths"))
        .toolbar { toolbar }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                openDrafts(urls)
            }
        }
        .sheet(isPresented: $showExport) {
            ExportView(session: session, format: $pendingFormat)
        }
        .sheet(isPresented: $showFilter) {
            FilterPopover(session: session)
                .frame(width: 440)
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveSheet(defaultName: defaultSaveName) { name in
                session.saveSnapshot(as: name)
            }
        }
        .sheet(isPresented: $session.showDiff) {
            DiffView(session: session)
        }
        .sheet(isPresented: $session.showDuplicates) {
            DuplicatesView(session: session)
        }
        .alert(Text("Scan error"), isPresented: errorPresented) {
            Button("OK") {}
        } message: {
            Text(session.scanError ?? "")
        }
        .onAppear {
            if let request {
                session.apply(request: request)
            } else if !MapWindowRoot.autoOpenHandled, let newest = library.savedMaps.first {
                // Cold start with no explicit target (no folder URL, no
                // service request): open the most recent saved map instead of
                // an empty draft.
                MapWindowRoot.autoOpenHandled = true
                request = MapWindowRequest.existing(newest.id)
            } else {
                MapWindowRoot.autoOpenHandled = true
            }
        }
        .onChange(of: request) { _, newValue in
            if let newValue { session.apply(request: newValue) }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppLibrary.folderRequestNotification)) { _ in
            let urls = library.takePendingURLs()
            for url in urls {
                // Item 10: the map appears in THIS window, not a new one.
                session.apply(request: MapWindowRequest.draft(path: url.path, name: url.lastPathComponent))
            }
        }
        .onChange(of: combinedSize) { _, newValue in
            var layout = session.columnLayout
            if newValue { layout.visible.removeAll { $0 == .sizeOnDisk } }
            if layout != session.columnLayout {
                session.columnLayout = layout
            }
            // When the layout is unchanged the @AppStorage flip still drives
            // updateNSView; Coordinator.sync notices the setting change and
            // rebuilds the header title + reloads cells.
        }
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            guard !folders.isEmpty else { return false }
            openDrafts(folders)
            return true
        }
        .background(QuickLookHost())
    }

    // MARK: - Detail area

    @ViewBuilder
    private var detail: some View {
        Group {
            if session.snapshot == nil && !session.isScanning {
                ContentUnavailableView {
                    Label("No map yet", systemImage: "map")
                } description: {
                    Text("Scan a folder to build its map, or open a saved map from the sidebar. You can also drop a folder here.")
                } actions: {
                    Button("Choose Folder…") { showImporter = true }
                }
            } else {
                Group {
                    switch session.layout {
                    case .list: NodeListView(session: session)
                    case .tree: NodeTreeView(session: session)
                    }
                }
                .allowsHitTesting(!session.isScanning)
                .overlay(alignment: .top) {
                    if !session.filter.isEmpty && session.layout == .tree {
                        Text("The filter is active — the tree shows the full map. Switch to the list layout for filtered results.")
                            .font(.caption)
                            .padding(6)
                            .background(.regularMaterial, in: .rect(cornerRadius: 8))
                            .padding(.top, 4)
                    }
                }
                // Option 4.2: while scanning, the content is dimmed and
                // non-interactive; a progress panel takes over.
                .overlay {
                    if session.isScanning {
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea()
                            VStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("Building map…")
                                    .font(.headline)
                                Text("\(session.progress.files + session.progress.folders) items · \(Fmt.size(session.progress.bytesProcessed))")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(session.progress.currentPath)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                    .frame(maxWidth: 420)
                                Button("Stop") {
                                    session.cancelScan()
                                }
                                .controlSize(.regular)
                            }
                            .padding(24)
                        }
                        // No .transition/animation here: animated conditional
                        // content inside the outline-table hierarchy crashes
                        // AttributeGraph during row-height sizing (see crash
                        // 609EF7EF). Appear/disappear must be abrupt.
                        .transaction { $0.animation = nil }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
        .safeAreaInset(edge: .bottom) { statusBar }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let snapshot = session.snapshot {
                Text("\(session.filteredFiles) files · \(session.filteredFolders) folders · \(Fmt.size(session.filteredSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if snapshot.header.errorCount > 0 {
                    Label("\(snapshot.header.errorCount)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Items with scan errors")
                }
                if let available = session.sourceAvailable {
                    if available {
                        Label("Source available", systemImage: "externaldrive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("The scanned source is reachable right now.")
                    } else {
                        Label("Source offline", systemImage: "externaldrive.badge.xmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("The source folder or disk is not reachable. The map still opens from saved metadata.")
                    }
                }
                if session.isEnriching, let enrichment = session.enrichmentProgress {
                    ProgressView(value: Double(enrichment.done), total: Double(max(1, enrichment.total)))
                        .frame(width: 120)
                    Text("\(enrichment.done)/\(enrichment.total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        session.cancelEnrichment()
                    } label: {
                        Image(systemName: "stop.circle")
                    }
                    .controlSize(.small)
                    .help("Stop metadata extraction")
                }
                Spacer(minLength: 0)
                if !session.selection.isEmpty {
                    Text("\(session.selection.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showImporter = true
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
            .help("Scan a folder")

            Button {
                Task { await session.rescan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(session.isScanning || (session.snapshot == nil && session.request?.sourcePath == nil))
            .help("Scan the source again")

            Picker("Layout", selection: $session.layout) {
                Label("List", systemImage: "list.bullet").tag(MapSession.Layout.list)
                Label("Tree", systemImage: "folder").tag(MapSession.Layout.tree)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Menu {
                Toggle(String(localized: "Combine Size / On disk"), isOn: $combinedSize)
                    .help(Text("On APFS, size on disk can be SMALLER than the file size — transparent compression, sparse files and clones are normal. This is not a bug."))
                Divider()
                ForEach(NodeColumn.pickerCases) { column in
                    Toggle(column.menuTitle, isOn: columnToggle(for: column))
                }
                Divider()
                Button("Reset Columns") {
                    session.columnLayout = .default
                    session.sortOrder = ColumnSort.defaults
                    NodeColumn.reset()
                }
            } label: {
                Label("Columns", systemImage: "tablecells")
            }
            .help("Choose columns")

            Button {
                showFilter = true
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filters")

            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.label) {
                        pendingFormat = format
                        showExport = true
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(session.snapshot == nil)
            .help("Export the map")

            Button {
                showSaveSheet = true
            } label: {
                Label("Save Map", systemImage: "tray.and.arrow.down")
            }
            .disabled(session.snapshot == nil || session.isScanning)
            .help("Save this map in the library")

            Menu {
                Menu("Compute SHA-256") {
                    ForEach(EnrichmentScope.allCases) { scope in
                        Button(scope.title) { session.computeChecksums(scope: scope) }
                    }
                }
                Menu("Extract media & EXIF") {
                    ForEach(EnrichmentScope.allCases) { scope in
                        Button(scope.title) { session.extractMediaMetadata(scope: scope) }
                    }
                }
            } label: {
                Label("Data", systemImage: "sparkles")
            }
            .disabled(session.snapshot == nil || session.isEnriching)

            Button {
                Task { await session.findDuplicates() }
            } label: {
                Label("Duplicates", systemImage: "doc.on.doc")
            }
            .disabled(session.snapshot == nil || session.isScanning || session.isEnriching)
            .help("Find duplicate files by content")

            Button {
                session.showDiff = true
            } label: {
                Label("Compare", systemImage: "arrow.left.arrow.right")
            }
            .disabled(session.snapshot == nil)
            .help("Compare with a saved map")

            Button {
                session.quickLookSelection()
            } label: {
                Label("Quick Look", systemImage: "eye")
            }
            .disabled(session.selectedNodes.isEmpty)
            .help("Quick Look the selection")

            Toggle(isOn: $session.inspectorVisible) {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show the inspector")
        }
    }

    private func columnToggle(for column: NodeColumn) -> Binding<Bool> {
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

    // MARK: - Helpers

    private var title: String {
        session.displayName.isEmpty ? String(localized: "FolderAtlas") : session.displayName
    }

    private var subtitle: String {
        if session.isScanning { return String(localized: "Scanning…") }
        guard let snapshot = session.snapshot else { return "" }
        return snapshot.header.sourcePath
    }

    private var defaultSaveName: String {
        if !session.displayName.isEmpty { return session.displayName }
        return session.snapshot?.header.displayName ?? "Map"
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { session.scanError != nil },
            set: { visible in if !visible { session.scanError = nil } })
    }

    private func openDrafts(_ urls: [URL]) {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        for (index, url) in folders.enumerated() {
            let request = MapWindowRequest.draft(path: url.path, name: url.lastPathComponent)
            if index == 0 {
                // Item 10: the first dropped folder opens in THIS window.
                session.apply(request: request)
            } else {
                openWindow(value: request)
            }
        }
    }
}

extension EnrichmentScope {
    var title: String {
        switch self {
        case .selection: return String(localized: "Selection")
        case .filtered: return String(localized: "Filtered results")
        case .all: return String(localized: "Whole map")
        }
    }
}

extension ExportFormat {
    var label: String {
        switch self {
        case .csv: return String(localized: "CSV")
        case .tsv: return String(localized: "TSV")
        case .json: return String(localized: "JSON")
        case .html: return String(localized: "HTML page")
        case .markdown: return String(localized: "Markdown")
        case .pdf: return String(localized: "PDF")
        case .xlsx: return String(localized: "Excel (.xlsx)")
        }
    }
}
