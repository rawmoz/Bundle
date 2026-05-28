import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Drag-out source for shelf slots.
//
// Why NSFilePromiseProvider instead of NSURL as pasteboard writer:
// Passing a raw file URL from ~/Library/Application Support/ causes Finder error -8058
// because Finder can't directly access that path from another process. With NSFilePromiseProvider,
// our app (which has full access to its own storage) copies the file to the system-provided
// destination URL — Finder never touches the source path directly.
//
// Completion flow: onDragComplete fires inside writePromiseTo after the copy succeeds,
// not at drag session end. This ensures storage is only cleared after the file is safe
// at its destination.

struct FileDragSource: NSViewRepresentable {
    let url: URL
    let icon: NSImage
    let onComplete: () -> Void

    func makeNSView(context: Context) -> FileDragSourceView {
        FileDragSourceView()
    }

    func updateNSView(_ nsView: FileDragSourceView, context: Context) {
        nsView.fileURL = url
        nsView.dragIcon = icon
        nsView.onDragComplete = onComplete
    }
}

final class FileDragSourceView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    var fileURL: URL?
    var dragIcon: NSImage?
    var onDragComplete: (() -> Void)?

    private var mouseDownEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url = fileURL, let mouseDown = mouseDownEvent else { return }

        let fileType = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.item.identifier
        let provider = NSFilePromiseProvider(fileType: fileType, delegate: self)
        provider.userInfo = url as NSURL

        let icon = dragIcon ?? NSWorkspace.shared.icon(forFile: url.path)
        let item = NSDraggingItem(pasteboardWriter: provider)
        let size = CGSize(width: 36, height: 36)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        item.setDraggingFrame(CGRect(origin: origin, size: size), contents: icon)

        beginDraggingSession(with: [item], event: mouseDown, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? URL)?.lastPathComponent ?? fileURL?.lastPathComponent ?? "file"
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo destURL: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let sourceURL = filePromiseProvider.userInfo as? URL else {
            completionHandler(CocoaError(.fileNoSuchFile))
            return
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            completionHandler(nil)
            DispatchQueue.main.async { [weak self] in
                self?.onDragComplete?()
            }
        } catch {
            completionHandler(error)
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
