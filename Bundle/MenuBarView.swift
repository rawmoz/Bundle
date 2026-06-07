import AppKit
import SwiftUI

struct MenuBarView: View {
    let manager: BundleManager
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeMenu(manager: manager) { path.append(CreateRoute()) }
                .navigationDestination(for: CreateRoute.self) { _ in
                    CreateBundleView(manager: manager) {
                        path = NavigationPath()
                        dismissPopover()
                    }
                }
        }
        .frame(width: 240)
        .background(.ultraThinMaterial)
    }
}

// Marker route so NavigationStack can push the creation page.
private struct CreateRoute: Hashable {}

private struct HomeMenu: View {
    let manager: BundleManager
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            MenuRow(title: "Add new bundle", icon: "plus", action: onAdd)
            MenuRow(title: "Show / Hide", icon: "eye") { manager.toggleAll() }
            Divider().padding(.vertical, 2)
            MenuRow(title: "Quit", icon: "power") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
    }
}

private struct CreateBundleView: View {
    let manager: BundleManager
    var onCreate: () -> Void

    @State private var name = ""
    @State private var columns = 3
    @State private var rows = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Bundle")
                .font(.headline)

            TextField("Bundle name", text: $name)
                .textFieldStyle(.roundedBorder)

            GridSizePicker(columns: $columns, rows: $rows)
                .frame(maxWidth: .infinity)

            Button(action: create) {
                Text("Create").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .navigationTitle("New Bundle")
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        manager.createBundle(
            name: trimmed.isEmpty ? "Untitled" : trimmed,
            columns: columns,
            rows: rows
        )
        onCreate()
    }
}

// Classic table-insert style picker: hover/tap to choose columns × rows, up to 5×5.
private struct GridSizePicker: View {
    @Binding var columns: Int
    @Binding var rows: Int

    private let maxSize = 5
    @State private var hover: (col: Int, row: Int)?

    var body: some View {
        let activeCols = hover?.col ?? columns
        let activeRows = hover?.row ?? rows

        VStack(spacing: 8) {
            VStack(spacing: 4) {
                ForEach(1...maxSize, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(1...maxSize, id: \.self) { c in
                            let on = c <= activeCols && r <= activeRows
                            RoundedRectangle(cornerRadius: 3)
                                .fill(on ? Color.accentColor : Color.white.opacity(0.12))
                                .frame(width: 24, height: 24)
                                .onHover { inside in if inside { hover = (c, r) } }
                                .onTapGesture { columns = c; rows = r }
                        }
                    }
                }
            }
            Text("\(activeCols) × \(activeRows)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .onHover { inside in if !inside { hover = nil } }
    }
}

private struct MenuRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(hovering ? Color.white.opacity(0.12) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MenuBarExtra (.window) has no official dismiss API; closing the key window
// collapses the popover after a text field or button has taken focus.
private func dismissPopover() {
    NSApp.keyWindow?.close()
}
