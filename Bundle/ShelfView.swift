import SwiftUI

struct ShelfView: View {
    var body: some View {
        VStack(spacing: ShelfConfig.slotSpacing) {
            ForEach(0..<ShelfConfig.slotCount, id: \.self) { _ in
                Circle()
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                    .frame(width: ShelfConfig.slotSize, height: ShelfConfig.slotSize)
            }
        }
        .padding(ShelfConfig.padding)
        .background(
            RoundedRectangle(cornerRadius: ShelfConfig.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}
