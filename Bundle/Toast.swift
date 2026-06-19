import AppKit
import SwiftUI

// Brief, auto-dismissing frosted notice — surfaces non-fatal outcomes that would
// otherwise be silent, like a multi-file paste overflowing a full bundle (v0.11).
// Deliberately decoupled from any bundle's grid: a standalone borderless panel that
// fades in over an anchor frame and fades itself back out, so any call site can use it
// without plumbing through the cell-action closures. Look-and-feel routes through
// BundleStyle, same as every other surface.
enum Toast {
    private static var panel: NSPanel?
    private static var dismiss: DispatchWorkItem?

    private static let visibleFor: TimeInterval = 2.2
    private static let fadeIn: TimeInterval = 0.18
    private static let fadeOut: TimeInterval = 0.25
    private static let gap: CGFloat = 8   // space between the bundle and the toast

    // Show `message` centered just above `anchor` (the bundle's panel frame), or
    // centered on the main screen if no anchor is on screen.
    static func show(_ message: String, over anchor: NSRect?) {
        dismiss?.cancel()

        let host = NSHostingView(rootView: ToastView(message: message))
        host.layout()
        let size = host.fittingSize

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(size)
        panel.contentView = host

        let area = anchor ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                     y: area.maxY + gap))

        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeIn
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { hide() }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleFor, execute: work)
    }

    private static func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeOut
            panel.animator().alphaValue = 0
        }, completionHandler: {
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true   // a passive notice, never steals interaction
        return panel
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(BundleStyle.headerColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(BundleStyle.panelMaterial, in: Capsule())
            .fixedSize()
    }
}
