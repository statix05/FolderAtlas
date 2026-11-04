import SwiftUI
import AppKit

/// Bridges Quick Look (QLPreviewPanel) with SwiftUI toolbar actions.
@preconcurrency import Quartz

@MainActor
final class QuickLookCenter: NSObject {
    static let shared = QuickLookCenter()

    private(set) var urls: [URL] = []

    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() as QLPreviewPanel? else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    /// Finder-style toggle: Space opens the preview for the given items, and
    /// pressing Space again (with the table focused again) closes it.
    func toggle(urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() as QLPreviewPanel? else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show(urls: urls)
        }
    }
}

@MainActor
extension QuickLookCenter: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index >= 0 && index < urls.count else { return nil }
        return urls[index] as NSURL
    }
}

/// Invisible hosting view that accepts QLPreviewPanel activation from the
/// responder chain (the standard macOS Quick Look integration path).
struct QuickLookHost: NSViewRepresentable {
    func makeNSView(context: Context) -> QLAcceptingView {
        QLAcceptingView()
    }

    func updateNSView(_ nsView: QLAcceptingView, context: Context) {}
}

final class QLAcceptingView: NSView {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookCenter.shared
        panel.delegate = QuickLookCenter.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}
