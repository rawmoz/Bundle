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

struct DragItem {
    let url: URL
    let icon: NSImage?
    let onComplete: () -> Void
}

struct FileDragSource: NSViewRepresentable {
    let items: [DragItem]
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> FileDragSourceView {
        FileDragSourceView()
    }

    func updateNSView(_ nsView: FileDragSourceView, context: Context) {
        nsView.dragItems = items
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

final class FileDragSourceView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    var dragItems: [DragItem] = []
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didDrag = false
    private var providerCompletions: [ObjectIdentifier: () -> Void] = [:]

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let mouseDown = mouseDownEvent, !dragItems.isEmpty else { return }
        let dx = event.locationInWindow.x - mouseDown.locationInWindow.x
        let dy = event.locationInWindow.y - mouseDown.locationInWindow.y
        guard dx * dx + dy * dy > 25 else { return } // 5pt threshold
        didDrag = true

        providerCompletions.removeAll()
        var nsDraggingItems: [NSDraggingItem] = []

        for item in dragItems {
            let fileType = UTType(filenameExtension: item.url.pathExtension)?.identifier ?? UTType.item.identifier
            let provider = NSFilePromiseProvider(fileType: fileType, delegate: self)
            provider.userInfo = item.url as NSURL
            providerCompletions[ObjectIdentifier(provider)] = item.onComplete

            let icon = item.icon ?? NSWorkspace.shared.icon(forFile: item.url.path)
            let draggingItem = NSDraggingItem(pasteboardWriter: provider)
            let size = CGSize(width: 36, height: 36)
            let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            draggingItem.setDraggingFrame(CGRect(origin: origin, size: size), contents: icon)
            nsDraggingItems.append(draggingItem)
        }

        beginDraggingSession(with: nsDraggingItems, event: mouseDown, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onSingleClick?()
        }
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? URL)?.lastPathComponent ?? "file"
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo destURL: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let sourceURL = filePromiseProvider.userInfo as? URL else {
            completionHandler(CocoaError(.fileNoSuchFile))
            return
        }
        let onComplete = providerCompletions[ObjectIdentifier(filePromiseProvider)]
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            completionHandler(nil)
            DispatchQueue.main.async { onComplete?() }
        } catch {
            completionHandler(error)
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
