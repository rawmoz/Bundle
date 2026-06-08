import SwiftUI

struct BundleGridView: View {
    let bundle: BundleState

    // Wired up by BundlePanelController — the view stays AppKit-agnostic.
    var onActivate: () -> Void      // make the panel key so the rename field can type
    var onDragChanged: () -> Void   // a drag is in progress on the handle
    var onDragEnded: () -> Void     // drag finished — controller saves position
    var onResize: () -> Void        // grid dimensions changed — controller resizes panel
    var onDelete: () -> Void        // delete this bundle

    @State private var showingSettings = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            VStack(spacing: BundleLayout.gap) {
                header
                grid
            }
            .padding(BundleLayout.pad)
        }
    }

    // Title row: bundle name on the left, `:::` grip on the right.
    private var header: some View {
        HStack(spacing: 8) {
            Text(bundle.name.isEmpty ? "Untitled" : bundle.name)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            grip
        }
        .frame(height: BundleLayout.headerHeight)
    }

    // The `:::` grip — the only interactive part of the header.
    // Hold + drag moves the panel; a plain click opens settings.
    private var grip: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 3) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(.white.opacity(0.45))
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
            showingSettings = true
        }
        .gesture(
            // minimumDistance > 0 keeps a still click as a tap (settings) and only
            // treats actual movement as a drag (move).
            DragGesture(minimumDistance: 4)
                .onChanged { _ in onDragChanged() }
                .onEnded { _ in onDragEnded() }
        )
        .popover(isPresented: $showingSettings, arrowEdge: .top) {
            BundleSettingsView(bundle: bundle, onResize: onResize, onDelete: onDelete)
        }
    }

    private var grid: some View {
        VStack(spacing: BundleLayout.gap) {
            ForEach(0..<bundle.rows, id: \.self) { _ in
                HStack(spacing: BundleLayout.gap) {
                    ForEach(0..<bundle.columns, id: \.self) { _ in
                        CellView()
                    }
                }
            }
        }
    }
}

// Settings popover anchored to the handle: rename, resize, delete.
private struct BundleSettingsView: View {
    @Bindable var bundle: BundleState
    var onResize: () -> Void
    var onDelete: () -> Void

    @State private var columns: Int
    @State private var rows: Int

    init(bundle: BundleState, onResize: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.bundle = bundle
        self.onResize = onResize
        self.onDelete = onDelete
        _columns = State(initialValue: bundle.columns)
        _rows = State(initialValue: bundle.rows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bundle Settings").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Bundle name", text: $bundle.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Size").font(.caption).foregroundStyle(.secondary)
                GridSizePicker(columns: $columns, rows: $rows)
                    .frame(maxWidth: .infinity)
            }
            .onChange(of: columns) { _, _ in applySize() }
            .onChange(of: rows) { _, _ in applySize() }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete Bundle", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(16)
        .frame(width: 240)
    }

    private func applySize() {
        bundle.resize(columns: columns, rows: rows)
        onResize()
    }
}
