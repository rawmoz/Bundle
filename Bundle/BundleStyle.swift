import SwiftUI

// Single source of the visual + motion vocabulary — the look-and-feel sibling of
// BundleLayout (which owns geometry). Every color, radius, material, font, ring width,
// and animation in the app routes through here, so the panels, cells, settings popover,
// and menu-bar popover can't drift apart, and a future restyle is a one-file change
// rather than a hunt through every view. Introduced in the v0.9 polish pass.
enum BundleStyle {

    // MARK: Surfaces
    static let panelMaterial: Material = .ultraThinMaterial
    static let panelCornerRadius: CGFloat = 20
    static let thumbnailCornerRadius: CGFloat = 8
    // The selection ring on an occupied cell sits just outside the rounded thumbnail,
    // so its corner radius is the thumbnail's plus the ring inset.
    static let thumbnailRingCornerRadius: CGFloat = 9

    // MARK: Selection & rings
    static let selectionColor: Color = .blue
    static let idleRingColor: Color = .white.opacity(0.3)
    static let selectedRingWidth: CGFloat = 2.5
    static let idleRingWidth: CGFloat = 1.5

    // MARK: Empty-cell fill (brighter while a drag hovers over it)
    static let emptyCellFill: Color = .white.opacity(0.08)
    static let emptyCellTargetedFill: Color = .white.opacity(0.18)

    // MARK: Typography & text
    static let cellNameFont: Font = .system(size: 8)
    static let cellNameColor: Color = .white.opacity(0.7)
    static let headerFont: Font = .system(size: 14, weight: .semibold)
    static let headerColor: Color = .white.opacity(0.85)
    static let gripColor: Color = .white.opacity(0.45)

    // MARK: Motion
    // Kept together so timing reads consistently and can be tuned in one place.
    enum Motion {
        // Panel show/hide fade — used by ⌘⌥B, launch restore, and create. Symmetric
        // in both directions so toggling all panels feels even.
        static let panelFadeDuration: TimeInterval = 0.22

        // Cell fill/clear — a soft spring so content pops in and eases out.
        static let cellContent: Animation = .spring(response: 0.32, dampingFraction: 0.72)

        // Drag-hover highlight on an empty cell — a quick, near-linear fade.
        static let cellHover: Animation = .easeOut(duration: 0.12)
    }
}
