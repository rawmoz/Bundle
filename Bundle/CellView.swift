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

    @State private var isTargeted = false

    private let thumbSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 3) {
            content
            if !cell.isEmpty, let name = cell.displayName {
                Text(name)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: BundleLayout.cellSize)
            }
        }
        .frame(width: BundleLayout.cellSize, height: BundleLayout.cellSize)
        .contentShape(Rectangle())
        // Double-click opens an occupied cell's content; single-click selects. The
        // count: 2 gesture must come first so a double-click isn't swallowed as a tap.
        .onTapGesture(count: 2) { if !cell.isEmpty { onOpen() } }
        .onTapGesture { onSelect() }
        .onDrop(of: [.bundleCell, .fileURL, .image, .text], isTargeted: $isTargeted) { onDropProviders($0) }
        .contextMenu {
            if cell.isEmpty {
                Button("Paste") { onPaste() }
            } else {
                Button("Delete Content", role: .destructive) { onDelete() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if cell.isEmpty {
            Circle()
                .fill(.white.opacity(isTargeted ? 0.18 : 0.08))
                .overlay(Circle().strokeBorder(ringColor, lineWidth: isSelected ? 2.5 : 1.5))
                .frame(width: BundleLayout.cellSize, height: BundleLayout.cellSize)
        } else {
            thumbnail
                .frame(width: thumbSize, height: thumbSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(ringColor, lineWidth: isSelected ? 2.5 : 0)
                )
                .onDrag {
                    onBeginDrag()       // record this cell as the drag source
                    return dragProvider()
                }
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
        isSelected ? .blue : .white.opacity(0.3)
    }
}
