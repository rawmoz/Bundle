import SwiftUI

struct BundleGridView: View {
    let bundle: BundleState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            VStack(spacing: 12) {
                ForEach(0..<bundle.rows, id: \.self) { _ in
                    HStack(spacing: 12) {
                        ForEach(0..<bundle.columns, id: \.self) { _ in
                            CellView()
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
