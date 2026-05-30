import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfView: View {
    @StateObject private var store = ShelfStore()
    @State private var dragOverIndex: Int? = nil
    @State private var selectedIndices: Set<Int> = []
    @State private var controlHeld = false
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
                        isSelected: selectedIndices.contains(index),
                        controlHeld: controlHeld,
                        dragItems: buildDragItems(for: index),
                        onSingleClick: { handleSingleClick(at: index) },
                        onDoubleClick: { handleDoubleClick(at: index) },
                        onReturn: { handleReturn(at: index) },
                        onTrash: { handleTrash(at: index) }
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
            .contentShape(Rectangle())
            .onTapGesture { selectedIndices = [] }
        }
        .background(
            RoundedRectangle(cornerRadius: ShelfConfig.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .onAppear { startModifierMonitor() }
        .onDisappear {
            stopModifierMonitor()
            selectedIndices = []
        }
    }

    // MARK: - Click handlers

    private func handleSingleClick(at index: Int) {
        if store.slots[index] == nil {
            selectedIndices = []
            return
        }
        selectedIndices = [index]
    }

    private func handleDoubleClick(at index: Int) {
        guard store.slots[index] != nil else { return }
        let targets = selectedIndices.contains(index) ? selectedIndices : [index]
        for i in targets {
            if let url = store.storageURL(at: i) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Batch operations

    private func handleReturn(at index: Int) {
        let targets = selectedIndices.contains(index) ? selectedIndices : [index]
        targets.forEach { store.returnToOrigin(at: $0) }
        selectedIndices.subtract(targets)
    }

    private func handleTrash(at index: Int) {
        let targets = selectedIndices.contains(index) ? selectedIndices : [index]
        targets.forEach { store.sendToTrash(at: $0) }
        selectedIndices.subtract(targets)
    }

    // MARK: - Multi-drag

    private func buildDragItems(for index: Int) -> [DragItem] {
        let indices = selectedIndices.contains(index)
            ? Array(selectedIndices).sorted()
            : [index]
        return indices.compactMap { i -> DragItem? in
            guard let url = store.storageURL(at: i) else { return nil }
            return DragItem(url: url, icon: nil, onComplete: { [store] in
                store.completeDragOut(at: i)
            })
        }
    }

    // MARK: - Drop

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

    // MARK: - Modifier key monitor

    private func startModifierMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            controlHeld = event.modifierFlags.contains(.control)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            DispatchQueue.main.async {
                controlHeld = event.modifierFlags.contains(.control)
            }
        }
    }

    private func stopModifierMonitor() {
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
    let isSelected: Bool
    let controlHeld: Bool
    let dragItems: [DragItem]
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void
    let onReturn: () -> Void
    let onTrash: () -> Void

    @State private var icon: NSImage? = nil

    var body: some View {
        ZStack {
            if isSelected && entry != nil {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: ShelfConfig.slotSize, height: ShelfConfig.slotSize)
            }

            Circle()
                .strokeBorder(borderColor, lineWidth: isSelected && entry != nil ? 2 : 1.5)
                .frame(width: ShelfConfig.slotSize, height: ShelfConfig.slotSize)

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ShelfConfig.slotSize * 0.65, height: ShelfConfig.slotSize * 0.65)
                    .overlay(
                        FileDragSource(
                            items: dragItems,
                            onSingleClick: onSingleClick,
                            onDoubleClick: onDoubleClick
                        )
                    )
            }

            if entry != nil {
                if controlHeld {
                    Button(action: onTrash) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red.opacity(0.9))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .offset(x: ShelfConfig.slotSize * 0.3, y: -ShelfConfig.slotSize * 0.3)
                } else if isSelected {
                    Button(action: onReturn) {
                        Image(systemName: "arrow.uturn.left")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .offset(x: ShelfConfig.slotSize * 0.3, y: -ShelfConfig.slotSize * 0.3)
                }
            }
        }
        .contentShape(Circle())
        .onTapGesture { onSingleClick() }
        .onChange(of: storageURL) { _, newURL in
            loadIcon(for: newURL)
        }
        .onAppear {
            loadIcon(for: storageURL)
        }
    }

    private var borderColor: Color {
        if isHighlighted { return .white.opacity(0.9) }
        if isSelected && entry != nil { return .accentColor }
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
