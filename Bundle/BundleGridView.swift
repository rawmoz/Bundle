import SwiftUI

struct BundleGridView: View {
    let bundle: BundleState
    let selection: SelectionStore

    // Wired up by BundlePanelController — the view stays AppKit-agnostic.
    var onActivate: () -> Void      // make the panel key so the rename field can type
    var onDragChanged: () -> Void   // a drag is in progress on the handle
    var onDragEnded: () -> Void     // drag finished — controller saves position
    var onResize: () -> Void        // grid dimensions changed — controller resizes panel
    var onDelete: () -> Void        // delete this bundle
    var onPersist: () -> Void       // save the bundle to disk (e.g. after a rename)
    var cellURL: (CellState) -> URL?            // resolve a cell's file for thumbnails
    var onDropCell: (Int, [NSItemProvider]) -> Bool   // content dragged into cell `Int`
    var onPasteCell: (Int) -> Void              // right-click Paste into cell `Int`
    var onDeleteCell: (Int) -> Void             // right-click Delete content of cell `Int`
    var onDragOutCell: (Int) -> Void            // cell `Int` was dragged out — clear it
    var onBeginDragCell: (Int) -> Void          // cell `Int`'s drag began — record source
    var onOpenCell: (Int) -> Void               // cell `Int` double-clicked — open content

    @State private var showingSettings = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                // Tapping empty space (padding/gaps, not a cell) clears the selection.
                .onTapGesture { selection.clear() }

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
            BundleSettingsView(bundle: bundle, onResize: onResize, onDelete: onDelete,
                               onPersist: onPersist, onDeleteContent: onDeleteCell)
        }
    }

    private var grid: some View {
        VStack(spacing: BundleLayout.gap) {
            ForEach(0..<bundle.rows, id: \.self) { row in
                HStack(spacing: BundleLayout.gap) {
                    ForEach(0..<bundle.columns, id: \.self) { col in
                        let index = row * bundle.columns + col
                        // Guard the transient during a resize where the row/column range
                        // can briefly outrun the (already trimmed) cells array.
                        if index < bundle.cells.count {
                            CellView(
                                cell: bundle.cells[index],
                                isSelected: selection.isSelected(bundleID: bundle.id, index: index),
                                contentURL: cellURL(bundle.cells[index]),
                                bundleID: bundle.id,
                                index: index,
                                onSelect: {
                                    selection.select(bundleID: bundle.id, index: index)
                                    onActivate()   // make the panel key so ⌘V/⌘C reach it
                                },
                                onDropProviders: { onDropCell(index, $0) },
                                onPaste: { onPasteCell(index) },
                                onDelete: { onDeleteCell(index) },
                                onDragOut: { onDragOutCell(index) },
                                onBeginDrag: { onBeginDragCell(index) },
                                onOpen: { onOpenCell(index) }
                            )
                        }
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
    var onPersist: () -> Void
    var onDeleteContent: (Int) -> Void   // trash a cell's file + clear it (for shrink)

    @State private var columns: Int
    @State private var rows: Int
    @State private var showShrinkAlert = false
    @State private var droppedCount = 0

    init(bundle: BundleState, onResize: @escaping () -> Void, onDelete: @escaping () -> Void,
         onPersist: @escaping () -> Void, onDeleteContent: @escaping (Int) -> Void) {
        self.bundle = bundle
        self.onResize = onResize
        self.onDelete = onDelete
        self.onPersist = onPersist
        self.onDeleteContent = onDeleteContent
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
            // Single key so picking a new size (which sets columns and rows together)
            // triggers one handler with the final values, not one per dimension.
            .onChange(of: columns * 100 + rows) { _, _ in sizeChanged() }

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
        // Save when the popover closes — catches a rename, which has no other trigger
        // (resize already persists via onResize). A redundant save here is harmless.
        .onDisappear { onPersist() }
        .alert("Make this bundle smaller?", isPresented: $showShrinkAlert) {
            Button("Cancel", role: .cancel) { revertSize() }
            Button("Resize", role: .destructive) { commitSize() }
        } message: {
            Text("This removes \(droppedCount) filled cell\(droppedCount == 1 ? "" : "s") "
               + "from the grid. The files stay saved in the bundle's folder, but those "
               + "cells will be cleared.")
        }
    }

    // A new size was chosen. If it would drop cells that currently hold content, confirm
    // first; otherwise apply immediately.
    private func sizeChanged() {
        guard columns != bundle.columns || rows != bundle.rows else { return }
        let newCount = columns * rows
        droppedCount = bundle.cells.enumerated()
            .filter { $0.offset >= newCount && !$0.element.isEmpty }
            .count
        if droppedCount > 0 {
            showShrinkAlert = true
        } else {
            commitSize()
        }
    }

    private func commitSize() {
        // Trash the files of any filled cells that are about to fall off the grid, then
        // resize. Trashed (recoverable), consistent with delete-content / delete-bundle.
        let newCount = columns * rows
        for i in bundle.cells.indices where i >= newCount && !bundle.cells[i].isEmpty {
            onDeleteContent(i)
        }
        bundle.resize(columns: columns, rows: rows)
        onResize()
    }

    // User cancelled a shrink — snap the picker back to the bundle's actual size.
    private func revertSize() {
        columns = bundle.columns
        rows = bundle.rows
    }
}
