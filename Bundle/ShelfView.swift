import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfView: View {
    @StateObject private var store = ShelfStore()
    @State private var dragOverIndex: Int? = nil
    @State private var commandHeld = false
    @State private var localMonitor: Any? = nil
    @State private var globalMonitor: Any? = nil

    var body: some View {
        VStack(spacing: 0) {
            PanelDragHandle()
                .frame(height: ShelfConfig.dragHandleHeight)

            VStack(spacing: ShelfConfig.slotSpacing) {
                ForEach(0..<ShelfConfig.slotCount, id: \.self) { index in
                    SlotView(
                        entry: store.slots[index],
                        storageURL: store.storageURL(at: index),
                        isHighlighted: dragOverIndex == index,
                        commandHeld: commandHeld,
                        onReturn: { store.returnToOrigin(at: index) },
                        onTrash: { store.sendToTrash(at: index) },
                        onDragOut: { store.completeDragOut(at: index) }
                    )
                    .onDrop(of: [.fileURL], isTargeted: Binding(
                        get: { dragOverIndex == index },
                        set: { dragOverIndex = $0 ? index : nil }
                    )) { providers in
                        handleDrop(providers: providers, into: index)
                    }
                }
            }
            .padding(ShelfConfig.padding)
        }
        .background(
            RoundedRectangle(cornerRadius: ShelfConfig.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .onAppear { startCommandMonitor() }
        .onDisappear { stopCommandMonitor() }
    }

    private func handleDrop(providers: [NSItemProvider], into index: Int) -> Bool {
        guard store.slots[index] == nil,
              let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                store.drop(url: url, into: index)
            }
        }
        return true
    }

    private func startCommandMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            commandHeld = event.modifierFlags.contains(.command)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            DispatchQueue.main.async {
                commandHeld = event.modifierFlags.contains(.command)
            }
        }
    }

    private func stopCommandMonitor() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}

// MARK: - Panel drag handle

struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView { DragHandleNSView() }
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}
}

final class DragHandleNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dotSize: CGFloat = 4
        let gap: CGFloat = 5
        let totalWidth = dotSize * 3 + gap * 2
        let startX = (bounds.width - totalWidth) / 2
        let y = (bounds.height - dotSize) / 2

        NSColor.white.withAlphaComponent(0.35).setFill()
        for i in 0..<3 {
            let x = startX + CGFloat(i) * (dotSize + gap)
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotSize, height: dotSize)).fill()
        }
    }
}

// MARK: - Slot view

struct SlotView: View {
    let entry: ShelfEntry?
    let storageURL: URL?
    let isHighlighted: Bool
    let commandHeld: Bool
    let onReturn: () -> Void
    let onTrash: () -> Void
    let onDragOut: () -> Void

    @State private var icon: NSImage? = nil
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(borderColor, lineWidth: 1.5)
                .frame(width: ShelfConfig.slotSize, height: ShelfConfig.slotSize)

            if let icon, let url = storageURL {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ShelfConfig.slotSize * 0.65, height: ShelfConfig.slotSize * 0.65)
                    .overlay(
                        FileDragSource(url: url, icon: icon, onComplete: onDragOut)
                    )
            }

            if entry != nil && (isHovering || commandHeld) {
                Button(action: commandHeld ? onTrash : onReturn) {
                    Image(systemName: commandHeld ? "trash.fill" : "arrow.uturn.left")
                        .foregroundColor(commandHeld ? .red.opacity(0.9) : .white.opacity(0.8))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .offset(x: ShelfConfig.slotSize * 0.3, y: -ShelfConfig.slotSize * 0.3)
            }
        }
        .onHover { isHovering = $0 }
        .onChange(of: storageURL) { _, newURL in
            loadIcon(for: newURL)
        }
        .onAppear {
            loadIcon(for: storageURL)
        }
    }

    private var borderColor: Color {
        if isHighlighted { return .white.opacity(0.9) }
        if entry != nil { return .white.opacity(0.6) }
        return .white.opacity(0.25)
    }

    private func loadIcon(for url: URL?) {
        guard let url else { icon = nil; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async { icon = img }
        }
    }
}
