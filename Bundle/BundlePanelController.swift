import AppKit
import SwiftUI

final class BundlePanelController {
    private let panel: NSPanel

    var isVisible: Bool { panel.isVisible }

    init(columns: Int, rows: Int) {
        let cellSize: CGFloat = 64
        let gap: CGFloat = 12
        let pad: CGFloat = 16

        let w = pad + CGFloat(columns) * cellSize + CGFloat(max(columns - 1, 0)) * gap + pad
        let h = pad + CGFloat(rows) * cellSize + CGFloat(max(rows - 1, 0)) * gap + pad

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: BundleGridView(columns: columns, rows: rows))
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: w, height: h))
        panel.contentView = hosting
        panel.center()
    }

    func show() { panel.orderFront(nil) }
    func hide() { panel.orderOut(nil) }
}
