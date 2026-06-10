import Foundation

// Tracks the one selected cell across every bundle. Selection is transient UI state
// (a blue ring + the target for ⌘V/⌘C) — it is never persisted. At most one cell is
// selected app-wide: selecting in one bundle deselects any cell in another.
@Observable
final class SelectionStore {
    private(set) var bundleID: UUID?
    private(set) var index: Int?

    func select(bundleID: UUID, index: Int) {
        self.bundleID = bundleID
        self.index = index
    }

    func clear() {
        bundleID = nil
        index = nil
    }

    func isSelected(bundleID: UUID, index: Int) -> Bool {
        self.bundleID == bundleID && self.index == index
    }
}
