import SwiftUI
import AppKit

/// Hashable weak reference — @FocusedObject requires ObservableObject, but
/// MapSession is @Observable (Observation), so the focused session travels
/// through FocusedValues as a boxed reference.
struct SessionRef: Hashable {
    weak var session: MapSession?

    static func == (lhs: SessionRef, rhs: SessionRef) -> Bool {
        lhs.session === rhs.session
    }

    func hash(into hasher: inout Hasher) {
        if let session { hasher.combine(ObjectIdentifier(session)) }
    }
}

struct FocusedSessionKey: FocusedValueKey {
    typealias Value = SessionRef
}

extension FocusedValues {
    var mapSessionRef: SessionRef? {
        get { self[FocusedSessionKey.self] }
        set { self[FocusedSessionKey.self] = newValue }
    }
}

/// Global macOS menu bar (P3.5): the owner's requirement — all settings of
/// all kinds live in the system menu bar, keyboard shortcuts wired to the
/// standard system shortcut handling. Every item is functional; nothing here
/// is decorative. Map actions act on the FOCUSED window's session.
struct AppCommands: Commands {

    // Shares the exact keys with the Settings window — menu and settings
    // cannot disagree.
    @AppStorage("scan.includeHidden") private var includeHidden = true
    @AppStorage("scan.includePackages") private var includePackages = true
    @AppStorage("scan.computeFolderSizes") private var computeFolderSizes = true
    @AppStorage(ViewSettings.combinedSizeKey) private var combinedSize = true
    @FocusedValue(\.mapSessionRef) private var sessionRef: SessionRef?

    private var session: MapSession? { sessionRef?.session }

    var body: some Commands {
        // MARK: File

        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Map")) {
                session?.request = nil
                session?.displayName = ""
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(session == nil)

            Button(String(localized: "Open Folder…")) { openFolder() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(session == nil)
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button(String(localized: "Rescan")) {
                guard let session else { return }
                Task { await session.rescan() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(session?.snapshot == nil || session?.isScanning == true)

            Button(String(localized: "Cancel Scan")) { session?.cancelScan() }
                .keyboardShortcut(.cancelAction)
                .disabled(session?.isScanning != true)

            Divider()
            Button(String(localized: "Save Map…")) {
                NotificationCenter.default.post(name: AppLibrary.saveRequestNotification, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(session?.snapshot == nil || session?.isScanning == true)

            Button(String(localized: "Export Map…")) {
                NotificationCenter.default.post(name: AppLibrary.exportRequestNotification, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(session?.snapshot == nil || session?.isScanning == true)
        }

        // MARK: Edit

        // The system already provides a localized Edit menu with standard
        // commands; adding our own created a duplicate (owner report). Nothing
        // to add here.

        // MARK: View — merge into the system View menu.

        CommandGroup(after: .toolbar) {
            Picker(String(localized: "Layout"), selection: layoutBinding) {
                Text(String(localized: "List"))
                    .tag(MapSession.Layout.list)
                    .keyboardShortcut("1", modifiers: .command)
                Text(String(localized: "Tree"))
                    .tag(MapSession.Layout.tree)
                    .keyboardShortcut("2", modifiers: .command)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(session == nil)

            Divider()
            Toggle(String(localized: "Folders First"), isOn: foldersFirstBinding)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(session == nil)
            Toggle(String(localized: "Show Size on Disk"), isOn: $combinedSize)

            Divider()
            Menu(String(localized: "Scanning")) {
                Toggle("Include hidden files", isOn: $includeHidden)
                Toggle("Include package contents (.app, .bundle...)", isOn: $includePackages)
                Toggle("Compute folder sizes and counts during scans", isOn: $computeFolderSizes)
            }
            .help(Text("These apply to the next scan; the current map keeps the settings it was scanned with."))
        }

        // MARK: Help — merge into the system Help menu.

        CommandGroup(after: .help) {
            Button(String(localized: "FolderAtlas on GitHub")) {
                if let url = URL(string: "https://github.com/statix05/FolderAtlas") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var layoutBinding: Binding<MapSession.Layout> {
        Binding(
            get: { session?.layout ?? .list },
            set: { session?.layout = $0 })
    }

    private var foldersFirstBinding: Binding<Bool> {
        Binding(
            get: { session?.foldersFirst ?? true },
            set: { session?.foldersFirst = $0 }) // setter already schedules a re-sort
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let session else { return }
        session.apply(request: MapWindowRequest.draft(path: url.path, name: url.lastPathComponent))
    }
}
