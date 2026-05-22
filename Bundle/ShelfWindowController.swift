import AppKit
import SwiftUI

final class ShelfWindowController: NSObject, NSWindowDelegate {
    private let panel: NSPanel

    override init() {
        let frame = NSRect(origin: ShelfConfig.savedPosition, size: ShelfConfig.panelSize)

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ShelfView())
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        panel.orderFront(nil)
    }

    private func hide() {
        panel.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        ShelfConfig.savedPosition = panel.frame.origin
    }
}
