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
            MenuRow(title: "Reveal in Finder", icon: "folder") { manager.revealBundlesFolder() }
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
