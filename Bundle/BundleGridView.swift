import SwiftUI

struct BundleGridView: View {
    let columns: Int
    let rows: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            VStack(spacing: 12) {
                ForEach(0..<rows, id: \.self) { _ in
                    HStack(spacing: 12) {
                        ForEach(0..<columns, id: \.self) { _ in
                            CellView()
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
