import Foundation

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

    init(id: UUID = UUID(), name: String, columns: Int, rows: Int) {
        self.id = id
        self.name = name
        self.columns = columns
        self.rows = rows
        self.cells = (0..<(columns * rows)).map { _ in CellState() }
    }
}
