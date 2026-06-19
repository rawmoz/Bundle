import Foundation
import CoreGraphics
import AppKit

// The on-disk shape of a bundle. This is deliberately separate from BundleState
// (the runtime model) so the persisted format can evolve independently. Only
// occupied cells are written — empty cells are implied by their absent index.
private struct BundleManifest: Codable {
    var id: String
    var name: String
    var columns: Int
    var rows: Int
    var positionX: Double?
    var positionY: Double?
    var cells: [CellManifest]

    init(from bundle: BundleState) {
        id = bundle.id.uuidString
        name = bundle.name
        columns = bundle.columns
        rows = bundle.rows
        positionX = bundle.position.map { Double($0.x) }
        positionY = bundle.position.map { Double($0.y) }
        cells = bundle.cells.enumerated().compactMap { index, cell in
            guard let type = cell.contentType,
                  let filename = cell.storedFilename,
                  let display = cell.displayName else { return nil }
            return CellManifest(index: index, contentType: type,
                                storedFilename: filename, displayName: display)
        }
    }

    func makeBundleState() -> BundleState? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let position: CGPoint? = {
            guard let x = positionX, let y = positionY else { return nil }
            return CGPoint(x: x, y: y)
        }()
        let state = BundleState(id: uuid, name: name, columns: columns, rows: rows, position: position)
        for cell in cells where cell.index < state.cells.count {
            state.cells[cell.index].contentType = cell.contentType
            state.cells[cell.index].storedFilename = cell.storedFilename
            state.cells[cell.index].displayName = cell.displayName
        }
        return state
    }
}

private struct CellManifest: Codable {
    var index: Int
    var contentType: CellContentType
    var storedFilename: String
    var displayName: String
}

// Owns the Bundles directory and all reads/writes. One UUID-named subdirectory per
// bundle holds that bundle's content files plus its manifest.json. Writes are tiny
// and synchronous — the manifest is a few hundred bytes, so a crash can never catch
// us mid-write (atomic writes) and there's nothing to gain from async here yet.
final class BundleStore {
    nonisolated let bundlesURL: URL   // immutable — safe to read off the main actor
    private let fm = FileManager.default

    // id → the bundle's *current* on-disk folder name. Folders are named after the human
    // bundle name (sanitized + uniquified), not the UUID, so Finder shows readable names.
    // The UUID stays the canonical key (it lives in manifest.json); this map resolves id →
    // folder. Populated by loadAll, kept current by save (rename) and deleteDirectory.
    private var folders: [UUID: String] = [:]

    init() {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        bundlesURL = appSupport.appendingPathComponent("Bundle/Bundles", isDirectory: true)
        try? fm.createDirectory(at: bundlesURL, withIntermediateDirectories: true)
    }

    // The directory that holds this bundle's manifest and content files. Resolves through
    // the folder-name map; falls back to the UUID for an id we haven't recorded yet (a
    // brand-new bundle is recorded by its first save, before any content is added).
    func directory(for id: UUID) -> URL {
        bundlesURL.appendingPathComponent(folders[id] ?? id.uuidString, isDirectory: true)
    }

    // Write (or overwrite) the bundle's manifest. Called on create, rename, resize,
    // move, and any cell content change — manifest always reflects current state. Also
    // the single chokepoint that keeps the folder name in sync with the bundle name:
    // reconcileFolder renames the folder on disk when the name changed.
    func save(_ bundle: BundleState) {
        let dir = reconcileFolder(for: bundle)
        let manifest = BundleManifest(from: bundle)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return }
        try? data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    // Scan the Bundles directory on launch and rebuild every bundle from its manifest.
    // Directories without a readable manifest are skipped, not deleted. Records each
    // bundle's actual folder name (could be a legacy UUID or a human name) into the map.
    func loadAll() -> [BundleState] {
        guard let entries = try? fm.contentsOfDirectory(
            at: bundlesURL, includingPropertiesForKeys: nil) else { return [] }
        var states: [BundleState] = []
        for entry in entries {
            let manifestURL = entry.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(BundleManifest.self, from: data),
                  let state = manifest.makeBundleState() else {
                continue
            }
            folders[state.id] = entry.lastPathComponent
            states.append(state)
        }
        return states
    }

    // Rename any legacy UUID-named folders to human names (migration for bundles created
    // before folders were named after the bundle). Safe to call every launch — bundles
    // already on a correct name are left untouched.
    func adoptHumanFolderNames(for bundles: [BundleState]) {
        for bundle in bundles { _ = reconcileFolder(for: bundle) }
    }

    // Send the whole bundle directory to the Trash — recoverable, never a hard delete.
    func deleteDirectory(for id: UUID) {
        let dir = directory(for: id)
        folders[id] = nil
        guard fm.fileExists(atPath: dir.path) else { return }
        try? fm.trashItem(at: dir, resultingItemURL: nil)
    }

    // Ensure the bundle's folder is named after its (sanitized, unique) name, renaming the
    // folder on disk if the name changed since the last save. Returns the current dir URL.
    @discardableResult
    private func reconcileFolder(for bundle: BundleState) -> URL {
        let desired = desiredFolderName(for: bundle)
        let current = folders[bundle.id]
        let dir = bundlesURL.appendingPathComponent(desired, isDirectory: true)
        if let current, current != desired {
            let from = bundlesURL.appendingPathComponent(current, isDirectory: true)
            if fm.fileExists(atPath: from.path) {
                // Rename the folder on disk. If the move fails, keep the old folder and
                // its name rather than creating an empty new folder that orphans content.
                do { try fm.moveItem(at: from, to: dir) }
                catch { return from }
            }
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        folders[bundle.id] = desired
        return dir
    }

    // The folder name this bundle should have: its sanitized name, made unique against
    // other bundles' folders and any unrelated folder already on disk (Finder-style " 2"
    // suffix). A bundle's own current folder never counts as a collision.
    private func desiredFolderName(for bundle: BundleState) -> String {
        let base = Self.sanitizeFolderName(bundle.name)
        let current = folders[bundle.id]
        func isFree(_ name: String) -> Bool {
            if name == current { return true }
            if folders.contains(where: { $0.key != bundle.id && $0.value == name }) { return false }
            return !fm.fileExists(atPath: bundlesURL.appendingPathComponent(name).path)
        }
        if isFree(base) { return base }
        var n = 2
        while true {
            let candidate = "\(base) \(n)"
            if isFree(candidate) { return candidate }
            n += 1
        }
    }

    // Make a bundle name safe to use as a folder name: strip path separators and other
    // illegal characters, collapse whitespace, drop leading dots (which hide the folder),
    // and fall back to "Untitled" when nothing usable remains.
    nonisolated static func sanitizeFolderName(_ name: String) -> String {
        var cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    // MARK: - Cell content

    // Full path to a stored content file within a bundle's directory.
    func contentFileURL(for id: UUID, filename: String) -> URL {
        directory(for: id).appendingPathComponent(filename)
    }

    // Bring an external file/folder into the bundle. Drag-in (`move: true`) is a real
    // move: relocate the file so the original is gone from its source folder — no copy
    // left behind, nothing in the Trash. We try a straight move first; if the sandbox
    // won't let us rename out of the source folder, we copy in and then permanently
    // delete the original (the bytes already live safely in the bundle), and only if we
    // can't even delete it do we fall back to trashing it. Paste passes move: false (the
    // clipboard only lends a reference, not ownership), so the source is left alone.
    // Returns the stored filename, made unique within the directory.
    func ingest(at source: URL, move: Bool, into id: UUID) -> String? {
        let dir = directory(for: id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = Self.uniqueName(source.lastPathComponent, in: dir)
        let dest = dir.appendingPathComponent(filename)

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        if move {
            if (try? fm.moveItem(at: source, to: dest)) != nil { return filename }
            guard (try? fm.copyItem(at: source, to: dest)) != nil else { return nil }
            if (try? fm.removeItem(at: source)) == nil {
                try? fm.trashItem(at: source, resultingItemURL: nil)   // last resort
            }
            return filename
        } else {
            return (try? fm.copyItem(at: source, to: dest)) != nil ? filename : nil
        }
    }

    // Move a content file from one bundle's folder to another's (internal cell
    // rearrange across bundles). Both folders live in our container, so a plain
    // moveItem works — no sandbox -8058 concern, no Trash. Returns the new filename,
    // uniquified against the destination folder.
    func moveContentBetweenBundles(filename: String, from sourceID: UUID, to destID: UUID) -> String? {
        let srcURL = contentFileURL(for: sourceID, filename: filename)
        guard fm.fileExists(atPath: srcURL.path) else { return nil }
        let destDir = directory(for: destID)
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let newName = Self.uniqueName(filename, in: destDir)
        let destURL = destDir.appendingPathComponent(newName)
        do { try fm.moveItem(at: srcURL, to: destURL); return newName }
        catch { return nil }
    }

    // Save a pasted/dropped image as PNG. Returns the stored filename.
    func saveImage(_ image: NSImage, into id: UUID) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let dir = directory(for: id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = Self.uniqueName("Image.png", in: dir)
        do { try png.write(to: dir.appendingPathComponent(filename)); return filename }
        catch { return nil }
    }

    // Save pasted/dropped plain text as a .txt file. Returns the stored filename.
    func saveText(_ text: String, into id: UUID) -> String? {
        let dir = directory(for: id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = Self.uniqueName("Text.txt", in: dir)
        do {
            try text.write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            return filename
        } catch { return nil }
    }

    // Move a single cell's content file to the Trash (explicit delete — recoverable).
    func removeContentFile(_ filename: String, bundleID: UUID) {
        let url = contentFileURL(for: bundleID, filename: filename)
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.trashItem(at: url, resultingItemURL: nil)
    }

    // Rename a cell's content file on disk, keeping its original extension. The new base
    // name is uniquified against the folder so two files can't collide. Returns the new
    // stored filename, or nil on failure / no-op (caller leaves the cell unchanged).
    func renameContentFile(_ filename: String, to newBaseName: String, bundleID: UUID) -> String? {
        let dir = directory(for: bundleID)
        let srcURL = dir.appendingPathComponent(filename)
        guard fm.fileExists(atPath: srcURL.path) else { return nil }
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let ext = (filename as NSString).pathExtension
        let desired = ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
        if desired == filename { return filename }   // unchanged
        let newName = Self.uniqueName(desired, in: dir)
        let destURL = dir.appendingPathComponent(newName)
        do { try fm.moveItem(at: srcURL, to: destURL); return newName }
        catch { return nil }
    }

    // Permanently delete a cell's content file (used after drag-out — it's a move, the
    // file now lives at the drop destination, so the bundle's copy is just redundant).
    func deleteContentFile(_ filename: String, bundleID: UUID) {
        let url = contentFileURL(for: bundleID, filename: filename)
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: url)
    }

    // Append " 2", " 3"… before the extension until the name is free in `dir`.
    nonisolated static func uniqueName(_ name: String, in dir: URL) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.appendingPathComponent(name).path) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) { return candidate }
            n += 1
        }
    }
}
