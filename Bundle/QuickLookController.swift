import AppKit
import Quartz

// Native macOS Quick Look preview of a cell's content — the floating mini-window you
// get from spacebar in Finder, for PDFs, images, folders, and text alike (v0.8).
//
// Why this drives the panel manually instead of the responder chain: QLPreviewPanel
// normally finds its controller by walking the responder chain
// (acceptsPreviewPanelControl), which assumes a conventional key-window app. This app
// is a menu-bar LSUIElement with borderless, non-activating panels, so there is no
// reliable responder-chain controller. We set the panel's dataSource/delegate directly
// and order it in ourselves.
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var url: URL?

    // Space on an occupied cell: open the preview, or close it if it's already up
    // (matching Finder's spacebar toggle). The caller only invokes this for occupied
    // cells, so `url` is always a real file here.
    func toggle(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        self.url = url
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        // The app is non-activating; bring it forward so the preview can take key,
        // otherwise the panel can appear behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        // NSURL conforms to QLPreviewItem; the bundle always hands us a real on-disk URL.
        (url as NSURL?) ?? NSURL(fileURLWithPath: "")
    }
}
