import AppKit
import SwiftUI
import Quartz

// Borderless panels can't become key by default, which would block the rename
// text field in the settings popover from accepting keystrokes. .nonactivatingPanel
// means becoming key still won't activate the app or steal focus from other apps.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class BundlePanelController {
    private let panel: KeyablePanel
    private var hosting: NSHostingView<BundleGridView>!
    let bundle: BundleState

    // Weak so the manager (which owns this controller) isn't retained back. Used to
    // route cell content actions — paste, copy-via-keyboard, drop, delete — to the
    // single source of truth.
    private weak var manager: BundleManager?

    // Shared selection — kept so we can clear it when this panel loses key focus
    // (clicking the desktop or another app deselects this bundle's cell).
    private let selection: SelectionStore
    private var resignObserver: NSObjectProtocol?

    // Set by BundleManager so a delete from the settings popover routes back to it.
    var onRequestDelete: (() -> Void)?

    // Set by BundleManager — called after the panel writes a new position (drag/resize)
    // so the change is saved to the bundle's manifest.json.
    var onPersist: (() -> Void)?

    // Mouse-to-origin offset captured at drag start (see handleDragChanged).
    private var dragOffset: CGSize?

    var isVisible: Bool { panel.isVisible }

    init(bundle: BundleState, selection: SelectionStore, manager: BundleManager) {
        self.bundle = bundle
        self.manager = manager
        self.selection = selection

        let size = BundleLayout.panelSize(columns: bundle.columns, rows: bundle.rows)
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = BundleGridView(
            bundle: bundle,
            selection: selection,
            onActivate: { [weak self] in self?.activate() },
            onDragChanged: { [weak self] in self?.handleDragChanged() },
            onDragEnded: { [weak self] in self?.handleDragEnded() },
            onResize: { [weak self] in self?.applyResize() },
            onDelete: { [weak self] in self?.onRequestDelete?() },
            onPersist: { [weak self] in self?.onPersist?() },
            cellURL: { [weak manager] cell in manager?.contentURL(for: bundle, cell: cell) },
            onDropCell: { [weak manager] index, providers in
                manager?.drop(providers: providers, into: bundle, index: index) ?? false
            },
            onPasteCell: { [weak manager] index in manager?.paste(into: bundle, index: index) },
            onDeleteCell: { [weak manager] index in manager?.deleteContent(bundle: bundle, index: index) },
            onDragOutCell: { [weak manager] index in manager?.moveOutContent(bundle: bundle, index: index) },
            onBeginDragCell: { [weak manager] index in manager?.beginCellDrag(bundle: bundle, index: index) },
            onOpenCell: { [weak manager] index in manager?.openContent(bundle: bundle, index: index) },
            onRevealCell: { [weak manager] index in manager?.revealContent(bundle: bundle, index: index) },
            onRenameCell: { [weak manager] index, name in manager?.renameContent(bundle: bundle, index: index, to: name) },
            onRevealBundle: { [weak manager] in manager?.revealBundleFolder(bundle) }
        )
        hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        // When this panel loses key focus, clear the selection — but only if the
        // selected cell still belongs to this bundle. Clicking another bundle's cell
        // sets the new selection *before* this panel resigns key, so that guard keeps
        // us from wiping a selection that has already moved elsewhere.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, self.selection.bundleID == self.bundle.id else { return }
            // Keep the selection if focus left only because Quick Look took key — the
            // cell should stay selected behind the preview, like a file in Finder, so
            // closing the preview returns to the same highlighted cell (v0.8).
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { return }
            self.selection.clear()
        }
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func show() {
        if let pos = bundle.position {
            let corrected = onScreenOrigin(for: pos)
            panel.setFrameOrigin(corrected)
            // The saved spot was off every display (e.g. an external screen was
            // disconnected) and got recentered — persist the rescue so it sticks.
            if corrected != pos {
                bundle.position = corrected
                onPersist?()
            }
        } else {
            panel.center()
            bundle.position = panel.frame.origin
        }
        // Fade in. Only snap to transparent if the panel was fully off-screen — re-showing
        // a panel that's still mid-fade-out just animates alpha back to 1 (no flicker), and
        // because toggleAll/⌘⌥B drive every panel through here, the whole set fades together.
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = BundleStyle.Motion.panelFadeDuration
            panel.animator().alphaValue = 1
        }
    }

    // Keep a restored bundle reachable: if its saved frame doesn't land on any current
    // display, it's stranded (a display was unplugged since last launch), so recenter it
    // on the main display. A frame that still touches a screen is left exactly as saved.
    private func onScreenOrigin(for origin: CGPoint) -> CGPoint {
        let frame = CGRect(origin: origin, size: panel.frame.size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            return origin
        }
        guard let visible = NSScreen.main?.visibleFrame else { return origin }
        return CGPoint(x: visible.midX - frame.width / 2,
                       y: visible.midY - frame.height / 2)
    }

    func hide() {
        // Fade out, then actually remove the panel. The completion re-checks alpha so a
        // re-show that interrupts the fade (alpha animated back toward 1) doesn't yank the
        // panel off-screen underneath itself.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = BundleStyle.Motion.panelFadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func activate() {
        panel.makeKeyAndOrderFront(nil)
    }

    // Drag uses the absolute mouse position rather than the gesture's translation:
    // moving the window mid-drag shifts the view under the cursor, which feeds back
    // into translation and causes jitter. mouseLocation is in screen coords (bottom-left
    // origin), immune to the window moving beneath it.
    private func handleDragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragOffset == nil {
            let origin = panel.frame.origin
            dragOffset = CGSize(width: mouse.x - origin.x, height: mouse.y - origin.y)
        }
        guard let off = dragOffset else { return }
        panel.setFrameOrigin(CGPoint(x: mouse.x - off.width, y: mouse.y - off.height))
    }

    private func handleDragEnded() {
        dragOffset = nil
        bundle.position = panel.frame.origin
        onPersist?()
    }

    // Resize the panel to the new grid dimensions, keeping the top-left corner fixed.
    // Origin is bottom-left, so a taller panel must push the origin down by the delta.
    private func applyResize() {
        let newSize = BundleLayout.panelSize(columns: bundle.columns, rows: bundle.rows)
        var frame = panel.frame
        let deltaHeight = newSize.height - frame.size.height
        frame.origin.y -= deltaHeight
        frame.size = newSize
        panel.setFrame(frame, display: true)
        hosting.frame = NSRect(origin: .zero, size: newSize)
        bundle.position = frame.origin
        onPersist?()
    }
}
