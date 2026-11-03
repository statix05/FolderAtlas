import AppKit

/// Handler for the Finder Services menu item declared in Info.plist
/// (NSMessage "makeFolderMap"). Receives the Finder selection as file URLs.
@MainActor
final class ServicesProvider: NSObject {

    @objc func makeFolderMap(_ pasteboard: NSPasteboard,
                             userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let folders = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        guard !folders.isEmpty else {
            error.pointee = String(localized: "Please select a folder.") as NSString
            return
        }
        AppLibrary.shared.submit(urls: folders)
    }
}
