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
        guard index < bundle.cells.count, let filename = bundle.cells[index].storedFilename else { return }
        store.deleteContentFile(filename, bundleID: bundle.id)
        clearCell(bundle, index)
    }

    // Handle a drag-in. Files are moved (drag-in ownership); images/text are written.
    // Loading is async, so the actual fill happens on the main queue after this returns.
    @discardableResult
    func drop(providers: [NSItemProvider], into bundle: BundleState, index: Int) -> Bool {
        guard index < bundle.cells.count, bundle.cells[index].isEmpty else { return false }
        guard !providers.isEmpty else { return false }

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

    // MARK: - Keyboard

    // ⌘V / ⌘C act on the selected cell. A local monitor fires while one of our panels
    // is key (selecting a cell makes its panel key, like the rename field does).
    // Returning nil swallows a handled event so the system doesn't beep.
    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.contains(.command),
                  let key = event.charactersIgnoringModifiers?.lowercased(),
                  let (bundle, index) = self.selectedCell() else { return event }
            if key == "v", self.paste(into: bundle, index: index) { return nil }
            if key == "c", self.copy(from: bundle, index: index) { return nil }
            return event
        }
    }

    private func selectedCell() -> (BundleState, Int)? {
        guard let id = selection.bundleID, let index = selection.index,
              let bundle = bundles.first(where: { $0.id == id }),
              index < bundle.cells.count else { return nil }
        return (bundle, index)
    }

    private func makeController(for state: BundleState) -> BundlePanelController {
        let controller = BundlePanelController(bundle: state, selection: selection, manager: self)
        controller.onRequestDelete = { [weak self] in self?.deleteBundle(state) }
        controller.onPersist = { [weak self] in self?.save(state) }
        controllers[state.id] = controller
        return controller
    }
}
