import SwiftUI

// Classic table-insert style picker: hover/tap to choose columns × rows, up to 5×5.
// Shared by the menu-bar creation page (MenuBarView) and the per-bundle settings
// popover (BundleGridView).
struct GridSizePicker: View {
    @Binding var columns: Int
    @Binding var rows: Int

    private let maxSize = 5
    @State private var hover: (col: Int, row: Int)?

    var body: some View {
        let activeCols = hover?.col ?? columns
        let activeRows = hover?.row ?? rows

        VStack(spacing: 8) {
            VStack(spacing: 4) {
                ForEach(1...maxSize, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(1...maxSize, id: \.self) { c in
                            let on = c <= activeCols && r <= activeRows
                            RoundedRectangle(cornerRadius: 3)
                                .fill(on ? Color.accentColor : Color.white.opacity(0.12))
                                .frame(width: 24, height: 24)
                                .onHover { inside in if inside { hover = (c, r) } }
                                .onTapGesture { columns = c; rows = r }
                        }
                    }
                }
            }
            Text("\(activeCols) × \(activeRows)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .onHover { inside in if !inside { hover = nil } }
    }
}
