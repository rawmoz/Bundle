import Foundation
import CoreGraphics
import UniformTypeIdentifiers

// What kind of item a cell holds. The stored file lives in the bundle's UUID
// directory; the manifest records which type so we pick the right thumbnail.
enum CellContentType: String, Codable {
    case file, folder, image, text
}

// Private drag payload identifying which cell a drag started from, so a drop onto
// another cell can be handled as an internal move/swap. The app generates its
// Info.plist, so there's no declared type to reference — we export one at runtime.
// Carried at .ownProcess visibility: Finder never sees it, and drag-OUT still uses
// the separate file promise on the same drag.
extension UTType {
    static let bundleCell = UTType(exportedAs: "com.danielramos.Bundle.cell")
}

struct CellDragPayload: Codable {
    let bundleID: UUID
    let index: Int
}

// One cell in a bundle grid. All content fields are nil when the cell is empty.
// `storedFilename` is the item's name *within* the bundle directory (not a full
// path); `displayName` is what shows under the thumbnail (filename, or the first
// ~25 chars for plain text).
struct CellState: Identifiable {
    let id = UUID()
    var contentType: CellContentType?
    var storedFilename: String?
    var displayName: String?

    var isEmpty: Bool { contentType == nil }
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

    // Resize the grid while preserving existing cell content. Cells are kept by
    // index: growing appends empty trailing slots, shrinking drops trailing slots.
    // A dropped slot's file is left on disk (orphaned, not deleted) so nothing is
    // ever silently destroyed by a resize.
    func resize(columns: Int, rows: Int) {
        let newCount = columns * rows
        if newCount < cells.count {
            cells = Array(cells.prefix(newCount))
        } else if newCount > cells.count {
            cells.append(contentsOf: (cells.count..<newCount).map { _ in CellState() })
        }
        self.columns = columns
        self.rows = rows
    }
}

// Single source of the panel geometry, shared by the SwiftUI layout (BundleGridView,
// CellView) and the AppKit panel sizing (BundlePanelController). Keeping the math in
// one place means the NSPanel frame and the SwiftUI content can never drift apart.
enum BundleLayout {
    static let cellSize: CGFloat = 64   // matches macOS Control Center small widget
    static let gap: CGFloat = 12        // spacing between cells and around the header
    static let pad: CGFloat = 16        // outer padding inside the rounded panel
    static let headerHeight: CGFloat = 18 // title row: name label + `:::` grip

    // Full panel size: outer padding + header + gap + grid (cells and inter-cell gaps).
    static func panelSize(columns: Int, rows: Int) -> CGSize {
        let width = pad + CGFloat(columns) * cellSize + CGFloat(max(columns - 1, 0)) * gap + pad
        let gridHeight = CGFloat(rows) * cellSize + CGFloat(max(rows - 1, 0)) * gap
        let height = pad + headerHeight + gap + gridHeight + pad
        return CGSize(width: width, height: height)
    }
}
