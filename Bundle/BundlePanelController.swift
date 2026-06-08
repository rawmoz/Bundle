import AppKit
import SwiftUI

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

    // Set by BundleManager so a delete from the settings popover routes back to it.
    var onRequestDelete: (() -> Void)?

    // Mouse-to-origin offset captured at drag start (see handleDragChanged).
    private var dragOffset: CGSize?

    var isVisible: Bool { panel.isVisible }

    init(bundle: BundleState) {
        self.bundle = bundle

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
            onActivate: { [weak self] in self?.activate() },
            onDragChanged: { [weak self] in self?.handleDragChanged() },
            onDragEnded: { [weak self] in self?.handleDragEnded() },
            onResize: { [weak self] in self?.applyResize() },
            onDelete: { [weak self] in self?.onRequestDelete?() }
        )
        hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
    }

    func show() {
        if let pos = bundle.position {
            panel.setFrameOrigin(pos)
        } else {
            panel.center()
            bundle.position = panel.frame.origin
        }
        panel.orderFront(nil)
    }

    func hide() { panel.orderOut(nil) }

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
        bundle.position = panel.frame.origin   // v0.4: persist to manifest.json here
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
        bundle.position = frame.origin   // v0.4: persist to manifest.json here
    }
}
