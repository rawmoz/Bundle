import Foundation
import CoreGraphics

// One cell in a bundle grid. Empty for now — content arrives in v0.4.
struct CellState: Identifiable {
    let id = UUID()
}

// A single bundle: a named grid of cells. Source of truth for one panel.
@Observable
final class BundleState: Identifiable {
    let id: UUID
    var name: String
    var columns: Int
    var rows: Int
    var cells: [CellState]

    // Panel origin in screen coordinates (AppKit bottom-left convention).
    // nil until the panel is first shown — the controller centers it and stores
    // the result back here.
    //
    // NOTE (v0.3): position lives in memory only. Bundles themselves are still
    // in-memory and vanish on relaunch, so there is nothing to restore onto yet.
    // The manifest.json save/restore arrives in v0.4 — the drag handler and
    // resize already write here so wiring persistence later is a one-line change.
    var position: CGPoint?

    init(id: UUID = UUID(), name: String, columns: Int, rows: Int, position: CGPoint? = nil) {
        self.id = id
        self.name = name
        self.columns = columns
        self.rows = rows
        self.position = position
        self.cells = (0..<(columns * rows)).map { _ in CellState() }
    }

    // Rebuild the cell grid for new dimensions. Cells are empty in v0.3 so this
    // simply resizes; content preservation across a resize arrives with v0.4 storage.
    func resize(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        self.cells = (0..<(columns * rows)).map { _ in CellState() }
    }
}

// Single source of the panel geometry, shared by the SwiftUI layout (BundleGridView,
// CellView) and the AppKit panel sizing (BundlePanelController). Keeping the math in
// one place means the NSPanel frame and the SwiftUI content can never drift apart.
enum BundleLayout {
    static let cellSize: CGFloat = 64   // matches macOS Control Center small widget
    static let gap: CGFloat = 12        // spacing between cells and around the handle
    static let pad: CGFloat = 16        // outer padding inside the rounded panel
    static let handleHeight: CGFloat = 10 // the `:::` drag handle row

    // Full panel size: outer padding + handle + gap + grid (cells and inter-cell gaps).
    static func panelSize(columns: Int, rows: Int) -> CGSize {
        let width = pad + CGFloat(columns) * cellSize + CGFloat(max(columns - 1, 0)) * gap + pad
        let gridHeight = CGFloat(rows) * cellSize + CGFloat(max(rows - 1, 0)) * gap
        let height = pad + handleHeight + gap + gridHeight + pad
        return CGSize(width: width, height: height)
    }
}
