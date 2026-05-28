import Foundation
import AppKit
import Combine

// MARK: - Storage strategy
//
// Move model: files are physically moved into app storage on drop.
// Original location is recorded and used for "return to origin."
// Shelf state persists across app launches via manifest.json.
//
// To swap back to reference model: replace `drop(url:into:)` to just set
// slots[index] directly without moving, and `storageURL(at:)` to return the
// original URL. Nothing else in the app holds URLs — all access goes through here.

struct ShelfEntry: Codable, Equatable {
    let uuid: String
    let originalPath: String
    let filename: String
}

private struct ManifestEntry: Codable {
    let slot: Int
    let uuid: String
    let originalPath: String
    let filename: String
}

final class ShelfStore: ObservableObject {
    @Published private(set) var slots: [ShelfEntry?]

    private let storageDir: URL
    private let manifestURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = appSupport.appendingPathComponent("Bundle/shelf")
        storageDir = base
        manifestURL = base.appendingPathComponent("manifest.json")
        slots = Array(repeating: nil, count: ShelfConfig.slotCount)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadManifest()
    }

    // MARK: - Drop in

    func drop(url: URL, into index: Int) {
        guard slots[index] == nil else { return }
        let uuid = UUID().uuidString
        let filename = url.lastPathComponent
        let destDir = storageDir.appendingPathComponent(uuid)
        let destURL = destDir.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destURL)
        } catch {
            // Cross-volume fallback: copy then delete original
            do {
                try FileManager.default.copyItem(at: url, to: destURL)
                try? FileManager.default.removeItem(at: url)
            } catch {
                try? FileManager.default.removeItem(at: destDir)
                return
            }
        }

        slots[index] = ShelfEntry(uuid: uuid, originalPath: url.path, filename: filename)
        saveManifest()
    }

    // MARK: - Return to origin

    func returnToOrigin(at index: Int) {
        guard let entry = slots[index] else { return }
        let src = storageURL(for: entry)
        let originalURL = URL(fileURLWithPath: entry.originalPath)
        let originalDir = originalURL.deletingLastPathComponent()

        let baseDestURL: URL
        if FileManager.default.fileExists(atPath: originalDir.path) {
            baseDestURL = originalURL
        } else {
            // Original directory gone — fall back to Downloads
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            baseDestURL = downloads.appendingPathComponent(entry.filename)
        }

        let destURL = uniqueDestination(for: baseDestURL)
        do {
            try FileManager.default.moveItem(at: src, to: destURL)
            try? FileManager.default.removeItem(at: storageDir.appendingPathComponent(entry.uuid))
            slots[index] = nil
            saveManifest()
        } catch {
            // Silent — file may have been externally moved while on shelf
        }
    }

    // MARK: - Send to trash (command-held)

    func sendToTrash(at index: Int) {
        guard let entry = slots[index] else { return }
        let fileURL = storageURL(for: entry)
        NSWorkspace.shared.recycle([fileURL]) { [weak self] _, error in
            guard error == nil, let self else { return }
            DispatchQueue.main.async {
                try? FileManager.default.removeItem(at: self.storageDir.appendingPathComponent(entry.uuid))
                self.slots[index] = nil
                self.saveManifest()
            }
        }
    }

    // MARK: - Drag out

    func storageURL(at index: Int) -> URL? {
        guard let entry = slots[index] else { return nil }
        return storageURL(for: entry)
    }

    // Called by the drag source on confirmed drag completion (not cancel)
    func completeDragOut(at index: Int) {
        guard let entry = slots[index] else { return }
        // File was moved by the drop target; clean up uuid folder if it still exists
        try? FileManager.default.removeItem(at: storageDir.appendingPathComponent(entry.uuid))
        slots[index] = nil
        saveManifest()
    }

    // MARK: - Helpers

    private func storageURL(for entry: ShelfEntry) -> URL {
        storageDir.appendingPathComponent(entry.uuid).appendingPathComponent(entry.filename)
    }

    private func uniqueDestination(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 1
        while true {
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            let candidate = dir.appendingPathComponent("\(name) \(i)\(suffix)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    // MARK: - Persistence

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data) else { return }
        for m in entries {
            guard m.slot < slots.count else { continue }
            let entry = ShelfEntry(uuid: m.uuid, originalPath: m.originalPath, filename: m.filename)
            guard FileManager.default.fileExists(atPath: storageURL(for: entry).path) else { continue }
            slots[m.slot] = entry
        }
    }

    private func saveManifest() {
        let entries = slots.enumerated().compactMap { index, entry -> ManifestEntry? in
            guard let entry else { return nil }
            return ManifestEntry(slot: index, uuid: entry.uuid, originalPath: entry.originalPath, filename: entry.filename)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: manifestURL)
    }
}
