import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Single source of truth — owns every bundle and its panel, the global hotkey, the
// shared cell selection, and the clipboard/drag routing. Persistence (v0.4) is
// delegated to BundleStore; this class decides *when* to save, the store decides *how*.
@Observable
final class BundleManager {
    private(set) var bundles: [BundleState] = []
    let selection = SelectionStore()

    private var controllers: [UUID: BundlePanelController] = [:]
    private let hotkeyManager = HotkeyManager()
    private let store = BundleStore()
    private var keyMonitor: Any?

    // The cell an in-app drag started from, recorded at drag start so a drop onto
    // another cell can be resolved as an internal move/swap (SwiftUI hands the drop an
    // empty item provider for in-app drags, so the source can't travel on the drag).
    private var pendingCellDrag: CellDragPayload?

    init() {
        hotkeyManager.onToggle = { [weak self] in self?.toggleAll() }
        hotkeyManager.register()
        installKeyboardMonitor()
        loadSavedBundles()
    }

    // Reconstruct every bundle saved to disk and show it in its restored position.
    private func loadSavedBundles() {
        let states = store.loadAll()
        store.adoptHumanFolderNames(for: states)   // migrate legacy UUID folders → human names
        for state in states {
            bundles.append(state)
            makeController(for: state).show()
        }
    }

    func createBundle(name: String, columns: Int, rows: Int) {
        let state = BundleState(name: name, columns: columns, rows: rows)
        bundles.append(state)
        makeController(for: state).show()   // show() assigns the centered position
        save(state)                         // ...which this first save then records
    }

    func deleteBundle(_ bundle: BundleState) {
        if selection.bundleID == bundle.id { selection.clear() }
        controllers[bundle.id]?.close()
        controllers[bundle.id] = nil
        bundles.removeAll { $0.id == bundle.id }
        store.deleteDirectory(for: bundle.id)
    }

    func toggleAll() {
        let all = Array(controllers.values)
        guard !all.isEmpty else { return }
        let allVisible = all.allSatisfy { $0.isVisible }
        all.forEach { allVisible ? $0.hide() : $0.show() }
    }

    // Persist a bundle's current state. Routed here from the panel controller on
    // drag-end and resize, from the settings popover on rename, and from every cell
    // content change below.
    func save(_ bundle: BundleState) {
        store.save(bundle)
    }

    // Open the folder where all bundle files live in Finder.
    func revealBundlesFolder() {
        NSWorkspace.shared.open(store.bundlesURL)
    }

    // Reveal a single bundle's folder in Finder, selected inside the Bundles directory
    // (from the bundle's settings popover). Path-agnostic — directory(for:) is whatever
    // BundleStore computes at runtime, so it's correct sandboxed or not.
    func revealBundleFolder(_ bundle: BundleState) {
        NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: bundle.id)])
    }

    // Reveal an occupied cell's file in Finder, highlighted inside its bundle's folder
    // (right-click on the cell). The seamless way to reach the real file behind a cell.
    func revealContent(bundle: BundleState, index: Int) {
        guard index < bundle.cells.count,
              let filename = bundle.cells[index].storedFilename else { return }
        NSWorkspace.shared.activateFileViewerSelecting(
            [store.contentFileURL(for: bundle.id, filename: filename)])
    }

    // Rename an occupied cell's backing file on disk to a new base name (the extension
    // is preserved by the store). The label tracks the new filename for everything but
    // text cells, whose label is a content preview rather than the filename.
    func renameContent(bundle: BundleState, index: Int, to newBaseName: String) {
        guard index < bundle.cells.count,
              let filename = bundle.cells[index].storedFilename,
              let newFilename = store.renameContentFile(filename, to: newBaseName, bundleID: bundle.id)
        else { return }
        bundle.cells[index].storedFilename = newFilename
        if bundle.cells[index].contentType != .text {
            bundle.cells[index].displayName = newFilename
        }
        save(bundle)
    }

    // Open an occupied cell's content in its default app (double-click, like Finder).
    func openContent(bundle: BundleState, index: Int) {
        guard index < bundle.cells.count,
              let filename = bundle.cells[index].storedFilename else { return }
        NSWorkspace.shared.open(store.contentFileURL(for: bundle.id, filename: filename))
    }

    // The on-disk URL backing an occupied cell, for thumbnails and copy-out.
    func contentURL(for bundle: BundleState, cell: CellState) -> URL? {
        guard let filename = cell.storedFilename else { return nil }
        return store.contentFileURL(for: bundle.id, filename: filename)
    }

    // MARK: - Cell content actions

    // Paste the clipboard into an empty cell. File URLs are copied (the clipboard only
    // lends a reference); images and text are written into the bundle. Returns whether
    // anything was pasted.
    @discardableResult
    func paste(into bundle: BundleState, index: Int) -> Bool {
        guard index < bundle.cells.count, bundle.cells[index].isEmpty else { return false }
        let pb = NSPasteboard.general
        // Multiple files spill-fill forward across empty cells from the selection (v0.11);
        // a single file behaves exactly as before. Paste is a copy, so any overflow leaves
        // the originals untouched on disk.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return spillFill(urls, into: bundle, from: index) {
                self.ingestURL($0, move: false, into: bundle, index: $1, save: false)
            }
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty {
            return spillFill(images, into: bundle, from: index) {
                self.ingestImage($0, into: bundle, index: $1, save: false)
            }
        }
        if let text = pb.string(forType: .string) {
            return ingestText(text, into: bundle, index: index)   // text is always single
        }
        return false
    }

    // v0.11 spill-fill engine (reused by v0.12 drag-in): place `items` one per empty cell,
    // walking forward from `start` in row-major reading order — ascending index *is* the
    // grid's reading order, so this is left→right, top→bottom. Occupied cells are skipped,
    // the walk never wraps backward, and the manifest is written once at the end rather
    // than per item. `ingest` runs only for items that found a cell, so a move-based source
    // (drag-in) never relocates anything it can't place.
    //
    // All-or-nothing: if there aren't enough empty cells (forward of `start`) for the whole
    // batch, nothing is placed — we tell the user and bail rather than partially filling.
    // Returns true if the batch was placed.
    @discardableResult
    private func spillFill<T>(_ items: [T], into bundle: BundleState, from start: Int,
                              ingest: (T, Int) -> Bool) -> Bool {
        let slots = emptyCellIndices(in: bundle, from: start)
        guard slots.count >= items.count else {
            notify("Not enough room for \(items.count) — only \(slots.count) free", for: bundle)
            return false
        }
        for (item, index) in zip(items, slots) { _ = ingest(item, index) }
        save(bundle)
        return true
    }

    // Indices of empty cells at or after `start`, in row-major reading order.
    private func emptyCellIndices(in bundle: BundleState, from start: Int) -> [Int] {
        guard start < bundle.cells.count else { return [] }
        return (start..<bundle.cells.count).filter { bundle.cells[$0].isEmpty }
    }

    // Brief, non-blocking notice anchored over a bundle — used when a paste/drag-in can't
    // place everything (overflow) so a partial fill isn't silent.
    private func notify(_ message: String, for bundle: BundleState) {
        Toast.show(message, over: controllers[bundle.id]?.frame)
    }

    // Copy an occupied cell's content to the clipboard, exactly like copying it in Finder.
    @discardableResult
    func copy(from bundle: BundleState, index: Int) -> Bool {
        guard index < bundle.cells.count,
              let type = bundle.cells[index].contentType,
              let filename = bundle.cells[index].storedFilename else { return false }
        let url = store.contentFileURL(for: bundle.id, filename: filename)
        let pb = NSPasteboard.general
        pb.clearContents()
        switch type {
        case .text:
            let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? bundle.cells[index].displayName ?? ""
            pb.setString(text, forType: .string)
        case .file, .folder, .image:
            pb.writeObjects([url as NSURL])
        }
        return true
    }

    // Explicit delete: send an occupied cell's file to the Trash and empty the cell.
    func deleteContent(bundle: BundleState, index: Int) {
        guard index < bundle.cells.count, let filename = bundle.cells[index].storedFilename else { return }
        store.removeContentFile(filename, bundleID: bundle.id)
        clearCell(bundle, index)
    }

    // Drag-out completed: the file now lives at the drop destination, so this is a move —
    // permanently remove the bundle's now-redundant copy and empty the cell.
    func moveOutContent(bundle: BundleState, index: Int) {
        pendingCellDrag = nil   // this drag left the app; it isn't an internal rearrange
        guard index < bundle.cells.count, let filename = bundle.cells[index].storedFilename else { return }
        store.deleteContentFile(filename, bundleID: bundle.id)
        clearCell(bundle, index)
    }

    // Record the cell an in-app drag started from (see pendingCellDrag / drop).
    func beginCellDrag(bundle: BundleState, index: Int) {
        pendingCellDrag = CellDragPayload(bundleID: bundle.id, index: index)
    }

    // Handle a drag-in. Files are moved (drag-in ownership); images/text are written.
    // Loading is async, so the actual fill happens on the main queue after this returns.
    @discardableResult
    func drop(providers: [NSItemProvider], into bundle: BundleState, index: Int) -> Bool {
        guard index < bundle.cells.count else { return false }

        // An internal cell→cell drag takes precedence: move (empty target) or swap
        // (occupied target). SwiftUI delivers an empty NSItemProvider for in-app drags,
        // so we can't read the source off the provider — instead the source cell is
        // recorded in memory when its drag begins (beginCellDrag). A real Finder file
        // always wins, so a stale value left by a cancelled drag can't hijack an
        // external drop.
        if let payload = pendingCellDrag, Self.dragFileURLs().isEmpty {
            pendingCellDrag = nil
            return rearrange(from: payload, toBundle: bundle, toIndex: index)
        }
        pendingCellDrag = nil

        // External content only ever fills an empty cell.
        guard bundle.cells[index].isEmpty, !providers.isEmpty else { return false }

        // Real files on disk (any type, images included) → move them: copy into the
        // bundle, then Trash the originals. We read the file URLs straight off the drag
        // pasteboard rather than via item-provider temp representations, which leak
        // staging folders in the sandbox. Multiple dragged files spill-fill forward across
        // empty cells from the drop target, exactly like multi-file paste (v0.11); a single
        // file fills just the drop-target cell as before. Drag-in is a move, but spill-fill
        // is all-or-nothing — on overflow nothing is placed, so nothing is moved off its
        // source (a file with no destination is never removed — see v0.4 move semantics).
        let fileURLs = Self.dragFileURLs()
        if !fileURLs.isEmpty {
            return spillFill(fileURLs, into: bundle, from: index) {
                self.ingestURL($0, move: true, into: bundle, index: $1, save: false)
            }
        }
        // No backing file (image data from a browser, dragged text) → save the raw data,
        // where there is no original to remove.
        loadData(from: providers, into: bundle, index: index)
        return true
    }

    // The source file URLs for the current drag, read directly from the drag pasteboard.
    // Returns the *real* paths for every file type — PDFs, images, folders — without the
    // file-url conformance gaps and temp-folder artifacts of item-provider loading. A
    // multi-file Finder drag yields every URL here (v0.12 spill-fill); the in-app cell→cell
    // drag yields none, which is how `drop` tells the two apart.
    private static func dragFileURLs() -> [URL] {
        let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls ?? []
    }

    // Fallback for drops with no backing file: raw image, then plain text.
    private func loadData(from providers: [NSItemProvider], into bundle: BundleState, index: Int) {
        let imageType = UTType.image.identifier
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(imageType) }) {
            provider.loadDataRepresentation(forTypeIdentifier: imageType) { [weak self] data, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.ingestImage(image, into: bundle, index: index) }
            }
            return
        }
        let textType = UTType.plainText.identifier
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            provider.loadDataRepresentation(forTypeIdentifier: textType) { [weak self] data, _ in
                guard let data, let text = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self?.ingestText(text, into: bundle, index: index) }
            }
        }
    }

    // MARK: - Ingest helpers

    @discardableResult
    private func ingestURL(_ url: URL, move: Bool, into bundle: BundleState, index: Int,
                           save: Bool = true) -> Bool {
        guard let filename = store.ingest(at: url, move: move, into: bundle.id) else { return false }
        fillCell(bundle, index, type: contentType(for: url),
                 filename: filename, display: url.lastPathComponent, save: save)
        return true
    }

    @discardableResult
    private func ingestImage(_ image: NSImage, into bundle: BundleState, index: Int,
                             save: Bool = true) -> Bool {
        guard let filename = store.saveImage(image, into: bundle.id) else { return false }
        fillCell(bundle, index, type: .image, filename: filename, display: filename, save: save)
        return true
    }

    @discardableResult
    private func ingestText(_ text: String, into bundle: BundleState, index: Int,
                            save: Bool = true) -> Bool {
        guard let filename = store.saveText(text, into: bundle.id) else { return false }
        let display = String(text.prefix(25))
        fillCell(bundle, index, type: .text, filename: filename,
                 display: display.isEmpty ? "Text" : display, save: save)
        return true
    }

    private func contentType(for url: URL) -> CellContentType {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return .folder }
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
            return .image
        }
        return .file
    }

    private func fillCell(_ bundle: BundleState, _ index: Int,
                          type: CellContentType, filename: String, display: String,
                          save: Bool = true) {
        guard index < bundle.cells.count else { return }
        bundle.cells[index].contentType = type
        bundle.cells[index].storedFilename = filename
        bundle.cells[index].displayName = display
        if save { self.save(bundle) }
    }

    private func clearCell(_ bundle: BundleState, _ index: Int) {
        bundle.cells[index].contentType = nil
        bundle.cells[index].storedFilename = nil
        bundle.cells[index].displayName = nil
        save(bundle)
    }

    // Set a cell's content from explicit fields (used when relocating content between
    // cells, where the source's type/display are carried over with a new filename).
    private func setCell(_ bundle: BundleState, _ index: Int,
                         type: CellContentType?, filename: String, display: String?) {
        guard index < bundle.cells.count else { return }
        bundle.cells[index].contentType = type
        bundle.cells[index].storedFilename = filename
        bundle.cells[index].displayName = display
        save(bundle)
    }

    // MARK: - Cell rearrange (internal drag between cells)

    // Handle an internal cell→cell drop. Empty target → move; occupied target → swap.
    // Within a bundle it's a pure slot swap (the files already live in that folder);
    // across bundles the backing files are physically moved between the two folders.
    // The source cell is only touched here, inside the target's drop handler, so a
    // cancelled drag changes nothing.
    @discardableResult
    private func rearrange(from payload: CellDragPayload, toBundle dest: BundleState, toIndex: Int) -> Bool {
        guard let source = bundles.first(where: { $0.id == payload.bundleID }),
              payload.index < source.cells.count,
              toIndex < dest.cells.count,
              !source.cells[payload.index].isEmpty else { return false }

        // Dropping a cell onto itself is a no-op.
        if source.id == dest.id, payload.index == toIndex { return true }

        if source.id == dest.id {
            // Same bundle: files already live here, so just swap the two slots. swapAt
            // covers both cases — empty target moves the content, occupied target swaps.
            dest.cells.swapAt(payload.index, toIndex)
            save(dest)
        } else if !moveBetweenBundles(source: source, sourceIndex: payload.index,
                                      dest: dest, destIndex: toIndex) {
            return false
        }

        selection.clear()   // the moved content's index changed — drop the stale ring
        return true
    }

    // Move/swap content across two bundles by relocating the backing files between
    // their folders, then updating both manifests. A real move (the source file is
    // gone once it lands), consistent with the drag-in/out semantics.
    private func moveBetweenBundles(source: BundleState, sourceIndex: Int,
                                    dest: BundleState, destIndex: Int) -> Bool {
        let s = source.cells[sourceIndex]
        let t = dest.cells[destIndex]
        guard let sFile = s.storedFilename else { return false }

        if t.isEmpty {
            guard let newName = store.moveContentBetweenBundles(
                filename: sFile, from: source.id, to: dest.id) else { return false }
            setCell(dest, destIndex, type: s.contentType, filename: newName, display: s.displayName)
            clearCell(source, sourceIndex)
        } else {
            guard let tFile = t.storedFilename,
                  let newS = store.moveContentBetweenBundles(filename: sFile, from: source.id, to: dest.id),
                  let newT = store.moveContentBetweenBundles(filename: tFile, from: dest.id, to: source.id)
            else { return false }
            setCell(dest, destIndex, type: s.contentType, filename: newS, display: s.displayName)
            setCell(source, sourceIndex, type: t.contentType, filename: newT, display: t.displayName)
        }
        return true
    }

    // MARK: - Keyboard

    // Keyboard acting on the selected cell. A local monitor fires while one of our
    // panels is key (selecting a cell makes its panel key, like the rename field does).
    // Two branches, both requiring a selected cell:
    //   • ⌘V / ⌘C — paste into / copy out of the cell (v0.4).
    //   • arrows / space — move the selection, or Quick Look the content (v0.8).
    // Returning nil swallows a handled event so the system doesn't beep.
    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let (bundle, index) = self.selectedCell() else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags.contains(.command) {
                // ⌘⌫ trashes an occupied cell's content (recoverable), like Finder.
                if event.keyCode == 51, !bundle.cells[index].isEmpty {
                    self.deleteContent(bundle: bundle, index: index)
                    return nil
                }
                guard let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
                if key == "v", self.paste(into: bundle, index: index) { return nil }
                if key == "c", self.copy(from: bundle, index: index) { return nil }
                return event
            }

            // Modifier-less navigation / preview. Arrow keys carry .function/.numericPad,
            // so we reject only command/control/option rather than requiring no flags.
            // Bail while a text field is editing so space stays typeable in the rename
            // field (a cell may still be selected behind the settings popover).
            guard !flags.contains(.control), !flags.contains(.option),
                  !self.isEditingText() else { return event }
            switch event.keyCode {
            case 123: self.moveSelection(.left, bundle: bundle, index: index);  return nil
            case 124: self.moveSelection(.right, bundle: bundle, index: index); return nil
            case 125: self.moveSelection(.down, bundle: bundle, index: index);  return nil
            case 126: self.moveSelection(.up, bundle: bundle, index: index);    return nil
            case 49:  self.previewSelectedCell(bundle: bundle, index: index);   return nil
            default:  return event
            }
        }
    }

    private func selectedCell() -> (BundleState, Int)? {
        guard let id = selection.bundleID, let index = selection.index,
              let bundle = bundles.first(where: { $0.id == id }),
              index < bundle.cells.count else { return nil }
        return (bundle, index)
    }

    // True while a text field has the field editor — e.g. the rename field in the
    // settings popover — so the arrow/space branch doesn't hijack normal typing.
    private func isEditingText() -> Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    private enum MoveDirection { case up, down, left, right }

    // Move the selection one cell within its bundle's grid. The grid is a flat array,
    // so up/down is a ±columns stride and left/right is ±1 with row-edge stops (no wrap).
    // A move that would leave the grid is ignored — the selection simply stays put.
    private func moveSelection(_ direction: MoveDirection, bundle: BundleState, index: Int) {
        let columns = bundle.columns
        let count = bundle.cells.count
        let column = index % columns
        var target = index
        switch direction {
        case .up:    if index - columns >= 0    { target = index - columns }
        case .down:  if index + columns < count { target = index + columns }
        case .left:  if column > 0              { target = index - 1 }
        case .right: if column < columns - 1    { target = index + 1 }
        }
        if target != index { selection.select(bundleID: bundle.id, index: target) }
    }

    // Space: toggle a native Quick Look preview of an occupied cell. On an empty cell
    // contentURL is nil, so nothing opens — but the caller still swallowed the event,
    // so the system doesn't beep.
    private func previewSelectedCell(bundle: BundleState, index: Int) {
        guard let url = contentURL(for: bundle, cell: bundle.cells[index]) else { return }
        QuickLookController.shared.toggle(url: url)
    }

    private func makeController(for state: BundleState) -> BundlePanelController {
        let controller = BundlePanelController(bundle: state, selection: selection, manager: self)
        controller.onRequestDelete = { [weak self] in self?.deleteBundle(state) }
        controller.onPersist = { [weak self] in self?.save(state) }
        controllers[state.id] = controller
        return controller
    }
}
