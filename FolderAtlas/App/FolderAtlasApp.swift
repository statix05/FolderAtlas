import SwiftUI
import AppKit

@main
struct FolderAtlasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = AppLibrary.shared

    var body: some Scene {
        WindowGroup(for: MapWindowRequest.self) { $request in
            MapWindowRoot(request: $request)
                .environment(library)
        }
        .defaultSize(width: 1150, height: 720)

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}
