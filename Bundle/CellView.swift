import SwiftUI

struct CellView: View {
    var body: some View {
        Circle()
            .fill(.white.opacity(0.08))
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1.5)
            )
            .frame(width: BundleLayout.cellSize, height: BundleLayout.cellSize)
    }
}
