import SwiftUI
import AppKit
import UniformTypeIdentifiers

// One cell. Empty cells are the familiar translucent circle; occupied cells show a
// thumbnail with the item name beneath, all within the fixed 64pt footprint so the
// panel geometry never changes. A blue ring marks the selected cell.
struct CellView: View {
    let cell: CellState
    let isSelected: Bool
    let contentURL: URL?
    let bundleID: UUID   // this cell's bundle + index, tagged onto an internal drag
    let index: Int       // so a drop onto another cell becomes a move/swap

    var onSelect: () -> Void
    var onDropProviders: ([NSItemProvider]) -> Bool
    var onPaste: () -> Void
    var onDelete: () -> Void
    var onDragOut: () -> Void   // drop was accepted elsewhere — remove from this cell
    var onBeginDrag: () -> Void // this cell's drag started — record it as the source
    var onOpen: () -> Void      // double-click — open the content in its default app
    var onReveal: () -> Void    // right-click — reveal this cell's file in Finder
    var onRename: (String) -> Void // right-click — rename the file on disk to a new base name

    @State private var isTargeted = false
    @State private var showingRename = false
    @State private var renameText = ""

    private let thumbSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 3) {
            content
            if !cell.isEmpty, let name = cell.displayName {
                Text(name)
                    .font(BundleStyle.cellNameFont)
                    .foregroundStyle(BundleStyle.cellNameColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: BundleLayout.cellSize)
            }
        }
        .frame(width: BundleLayout.cellSize, height: BundleLayout.cellSize)
        // Animate the empty↔occupied switch (fill on paste/drop, clear on delete/move-out)
        // and the drag-hover highlight. Both key off observable cell state, so a content
        // change anywhere routes through here and the cell visibly pops in / eases out.
        .animation(BundleStyle.Motion.cellContent, value: cell.isEmpty)
        .animation(BundleStyle.Motion.cellHover, value: isTargeted)
        .contentShape(Rectangle())
        // Double-click opens an occupied cell's content; single-click selects. The
        // select is a *simultaneous* gesture so it fires on the first click immediately
        // instead of waiting out the double-click interval to disambiguate (the old
        // count:1 + count:2 pair forced a ~1s wait before selecting). A double-click
        // harmlessly runs onSelect() first, then onOpen() — same cell, no side effect.
        // This matches how native AppKit apps feel: act now, don't wait for a maybe-second-click.
        .onTapGesture(count: 2) { if !cell.isEmpty { onOpen() } }
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .onDrop(of: [.bundleCell, .fileURL, .image, .text], isTargeted: $isTargeted) { onDropProviders($0) }
        .contextMenu {
            if cell.isEmpty {
                Button("Paste") { onPaste() }
            } else {
                Button("Reveal in Finder") { onReveal() }
                Button("Rename…") {
                    onSelect()                       // make the panel key so the field can type
                    renameText = renameBaseName
                    showingRename = true
                }
                Button(role: .destructive) { onDelete() } label: {
                    Text("Delete Content").foregroundStyle(.red)
                }
            }
        }
        .popover(isPresented: $showingRename, arrowEdge: .bottom) { renamePopover }
    }

    // Rename the on-disk file. Pre-fills the current base name (extension is preserved
    // by the store); submitting an empty/blank name is a no-op.
    private var renamePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename").font(.headline)
            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { commitRename() }
            HStack {
                Spacer()
                Button("Cancel") { showingRename = false }
                Button("Rename") { commitRename() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    // The current file's base name (no extension) — the editable part of the rename.
    private var renameBaseName: String {
        ((cell.storedFilename ?? "") as NSString).deletingPathExtension
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onRename(trimmed) }
        showingRename = false
    }

    @ViewBuilder
    private var content: some View {
        if cell.isEmpty {
            Circle()
                .fill(isTargeted ? BundleStyle.emptyCellTargetedFill : BundleStyle.emptyCellFill)
                .overlay(Circle().strokeBorder(ringColor, lineWidth: ringWidth))
                .frame(width: BundleLayout.cellSize, height: BundleLayout.cellSize)
                // Cleared cells fade back to the empty slot.
                .transition(.opacity)
        } else {
            thumbnail
                .frame(width: thumbSize, height: thumbSize)
                .overlay(
                    RoundedRectangle(cornerRadius: BundleStyle.thumbnailRingCornerRadius)
                        .strokeBorder(ringColor, lineWidth: isSelected ? BundleStyle.selectedRingWidth : 0)
                )
                .onDrag {
                    onBeginDrag()       // record this cell as the drag source
                    return dragProvider()
                }
                // Filled content pops in (scale up from the slot center) and out.
                .transition(.scale(scale: 0.55).combined(with: .opacity))
        }
    }

    // Drag-out as a *move*. We hand the receiver a file *promise* (not the raw
    // container URL — dragging a URL straight out of the sandbox makes Finder throw
    // error -8058). The promise's load handler only fires once a destination accepts
    // the drop, so a cancelled drag changes nothing. On acceptance we deliver an
    // independent temp copy, then `onDragOut` removes the original from the cell (to
    // the Trash — recoverable). If staging the temp copy fails we deliver the original
    // and leave the cell untouched, so the file is never lost.
    private func dragProvider() -> NSItemProvider {
        guard let url = contentURL else { return NSItemProvider() }
        let provider = NSItemProvider()
        provider.suggestedName = (url.lastPathComponent as NSString).deletingPathExtension
        let type: UTType = cell.contentType == .folder
            ? .folder
            : (UTType(filenameExtension: url.pathExtension) ?? .data)
        let onDragOut = self.onDragOut
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all
        ) { completion in
            do {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let temp = tempDir.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: temp)
                completion(temp, false, nil)            // deliver the copy
                DispatchQueue.main.async { onDragOut() } // then clear the original
            } catch {
                completion(url, false, nil)             // fallback: copy-out, keep the cell
            }
            return nil
        }
        // Also tag the drag with this cell's identity so a drop onto another cell is
        // handled internally as a move/swap. .ownProcess keeps it out of Finder, where
        // the file promise above is what counts.
        if let data = try? JSONEncoder().encode(CellDragPayload(bundleID: bundleID, index: index)) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.bundleCell.identifier, visibility: .ownProcess
            ) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    @ViewBuilder
    private var thumbnail: some View {
        if cell.contentType == .image, let url = contentURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbSize, height: thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: thumbSize, height: thumbSize)
        }
    }

    // Native macOS icon for the stored file/folder (or a generic doc as a fallback).
    private var fileIcon: NSImage {
        if let url = contentURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    private var ringColor: Color {
        isSelected ? BundleStyle.selectionColor : BundleStyle.idleRingColor
    }

    // Empty-cell ring: thicker when selected, the thin idle ring otherwise.
    private var ringWidth: CGFloat {
        isSelected ? BundleStyle.selectedRingWidth : BundleStyle.idleRingWidth
    }
}
