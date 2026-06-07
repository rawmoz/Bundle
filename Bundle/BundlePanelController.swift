import AppKit
import SwiftUI

final class BundlePanelController {
    private let panel: NSPanel
    let bundle: BundleState

    var isVisible: Bool { panel.isVisible }

    init(bundle: BundleState) {
        self.bundle = bundle

        let cellSize: CGFloat = 64
        let gap: CGFloat = 12
        let pad: CGFloat = 16

        let w = BundlePanelController.span(count: bundle.columns, cellSize: cellSize, gap: gap, pad: pad)
        let h = BundlePanelController.span(count: bundle.rows, cellSize: cellSize, gap: gap, pad: pad)

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

        let hosting = NSHostingView(rootView: BundleGridView(bundle: bundle))
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: w, height: h))
        panel.contentView = hosting
        panel.center()
    }

    func show() { panel.orderFront(nil) }
    func hide() { panel.orderOut(nil) }

    // Total panel dimension along one axis: outer padding + cells + inter-cell gaps.
    private static func span(count: Int, cellSize: CGFloat, gap: CGFloat, pad: CGFloat) -> CGFloat {
        let cells = CGFloat(count) * cellSize
        let gaps = CGFloat(max(count - 1, 0)) * gap
        return pad + cells + gaps + pad
    }
}
