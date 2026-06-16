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
        for state in store.loadAll() {
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
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            return ingestURL(url, move: false, into: bundle, index: index)
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return ingestImage(image, into: bundle, index: index)
        }
        if let text = pb.string(forType: .string) {
            return ingestText(text, into: bundle, index: index)
        }
        return false
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
        if let payload = pendingCellDrag, Self.dragFileURL() == nil {
            pendingCellDrag = nil
            return rearrange(from: payload, toBundle: bundle, toIndex: index)
        }
        pendingCellDrag = nil

        // External content only ever fills an empty cell.
        guard bundle.cells[index].isEmpty, !providers.isEmpty else { return false }

        // A real file on disk (any type, images included) → move it: copy into the
        // bundle, then Trash the original. We read the file URL straight off the drag
        // pasteboard rather than via item-provider temp representations, which leak
        // staging folders in the sandbox.
        if let url = Self.dragFileURL(), url.isFileURL {
            ingestURL(url, move: true, into: bundle, index: index)
            return true
        }
        // No backing file (image data from a browser, dragged text) → save the raw data,
        // where there is no original to remove.
        loadData(from: providers, into: bundle, index: index)
        return true
    }

    // The source file URL for the current drag, read directly from the drag pasteboard.
    // Returns the *real* path for every file type — PDFs, images, folders — without the
    // file-url conformance gaps and temp-folder artifacts of item-provider loading.
    private static func dragFileURL() -> URL? {
        let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first
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
    private func ingestURL(_ url: URL, move: Bool, into bundle: BundleState, index: Int) -> Bool {
        guard let filename = store.ingest(at: url, move: move, into: bundle.id) else { return false }
        fillCell(bundle, index, type: contentType(for: url),
                 filename: filename, display: url.lastPathComponent)
        return true
    }

    @discardableResult
    private func ingestImage(_ image: NSImage, into bundle: BundleState, index: Int) -> Bool {
        guard let filename = store.saveImage(image, into: bundle.id) else { return false }
        fillCell(bundle, index, type: .image, filename: filename, display: filename)
        return true
    }

    @discardableResult
    private func ingestText(_ text: String, into bundle: BundleState, index: Int) -> Bool {
        guard let filename = store.saveText(text, into: bundle.id) else { return false }
        let display = String(text.prefix(25))
        fillCell(bundle, index, type: .text, filename: filename,
                 display: display.isEmpty ? "Text" : display)
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
                          type: CellContentType, filename: String, display: String) {
        guard index < bundle.cells.count else { return }
        bundle.cells[index].contentType = type
        bundle.cells[index].storedFilename = filename
        bundle.cells[index].displayName = display
        save(bundle)
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
