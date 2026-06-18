import AppKit
import SwiftUI

struct MenuBarView: View {
    let manager: BundleManager
    @State private var showingCreate = false

    var body: some View {
        Group {
            if showingCreate {
                CreateBundleView(
                    manager: manager,
                    onCancel: { showingCreate = false },
                    onCreate: {
                        showingCreate = false
                        dismissPopover()
                    }
                )
            } else {
                HomeMenu(manager: manager) { showingCreate = true }
            }
        }
        // Lock the popover to one fixed size — tall enough for the create form with the
        // full 5×5 grid picker. MenuBarExtra(.window) only ever grows its window to fit
        // content and never shrinks back; by never letting the size change, that bug can't
        // fire and there's no oversized window background peeking out as a second frame.
        // Pages top-align so the shorter home menu's spare room sits at the bottom.
        .frame(width: 240, height: 330, alignment: .top)
    }
}

private struct HomeMenu: View {
    let manager: BundleManager
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if manager.bundles.isEmpty {
                emptyPrompt
            }
            MenuRow(title: "Add new bundle", icon: "plus", action: onAdd)
            MenuRow(title: "Show / Hide", icon: "eye") { manager.toggleAll() }
            MenuRow(title: "Reveal in Finder", icon: "folder") { manager.revealBundlesFolder() }
            Divider().padding(.vertical, 2)
            MenuRow(title: "Quit", icon: "power") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
    }

    // First-launch friendly prompt — shown above the menu when no bundles exist yet so
    // the popover doesn't open looking bare and inert.
    private var emptyPrompt: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No bundles yet")
                .font(.headline)
            Text("Create your first bundle to collect files, folders, and notes on your desktop.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }
}

private struct CreateBundleView: View {
    let manager: BundleManager
    var onCancel: () -> Void
    var onCreate: () -> Void

    @State private var name = ""
    @State private var columns = 3
    @State private var rows = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                Text("New Bundle").font(.headline)
            }

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
