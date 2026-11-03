import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The service provider must exist before service requests are delivered
        // (a cold launch through Finder → Services delivers the request during launch).
        NSApp.servicesProvider = ServicesProvider()
    }

    /// Folders dropped onto the dock icon or opened via "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        AppLibrary.shared.submit(urls: urls)
    }
}
