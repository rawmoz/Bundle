import Foundation

// Tracks the selected cells across every bundle. Selection is transient UI state
// (a blue ring + the target for ⌘V/⌘C/⌘⌫/drag-out) — it is never persisted.
//
// v0.14: selection is now a *set* of cells, but scoped to a single bundle at a time
// (⌘-clicking a cell in another bundle starts fresh there). `indices` holds every
// selected cell; `anchor` is the "active" one that single-cell commands collapse to —
// arrow-key navigation, Quick Look, rename, and double-click open all act on the anchor,
// exactly like Finder collapses those to the active item.
@Observable
final class SelectionStore {
    private(set) var bundleID: UUID?
    private(set) var indices: Set<Int> = []
    private(set) var anchor: Int?

    // The anchor cell — the single cell that keyboard nav / Quick Look / rename act on.
    // Kept as `index` so existing single-cell callers (e.g. the keyboard monitor) read it
    // unchanged.
    var index: Int? { anchor }

    // Plain click: reset to a single selected cell (clears any multi-selection), exactly
    // like clicking a file in Finder.
    func select(bundleID: UUID, index: Int) {
        self.bundleID = bundleID
        self.indices = [index]
        self.anchor = index
    }

    // ⌘-click: toggle a cell in/out of the selection. Selecting a cell in a different
    // bundle starts a fresh single selection there (single-bundle scope, v0.14). Removing
    // the last cell clears the selection entirely.
    func toggle(bundleID: UUID, index: Int) {
        guard self.bundleID == bundleID else {
            select(bundleID: bundleID, index: index)
            return
        }
        if indices.contains(index) {
            indices.remove(index)
            if indices.isEmpty {
                clear()
            } else if anchor == index {
                anchor = indices.min()   // promote a remaining cell to anchor
            }
        } else {
            indices.insert(index)
            anchor = index
        }
    }

    func clear() {
        bundleID = nil
        indices = []
        anchor = nil
    }

    func isSelected(bundleID: UUID, index: Int) -> Bool {
        self.bundleID == bundleID && indices.contains(index)
    }

    // Every selected cell index in this bundle, in row-major reading order. Used by the
    // batch commands (delete / copy / drag-out) so they act on the cells predictably.
    func selectedIndices(in bundleID: UUID) -> [Int] {
        self.bundleID == bundleID ? indices.sorted() : []
    }
}
