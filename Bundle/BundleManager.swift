import AppKit
import SwiftUI

// Single source of truth — owns every bundle and its panel, plus the global hotkey.
// Replaces the v0.1 AppCoordinator. Persistence lands in v0.4.
@Observable
final class BundleManager {
    private(set) var bundles: [BundleState] = []
    private var controllers: [UUID: BundlePanelController] = [:]
    private let hotkeyManager = HotkeyManager()

    init() {
        hotkeyManager.onToggle = { [weak self] in self?.toggleAll() }
        hotkeyManager.register()
    }

    func createBundle(name: String, columns: Int, rows: Int) {
        let state = BundleState(name: name, columns: columns, rows: rows)
        bundles.append(state)
        let controller = BundlePanelController(bundle: state)
        controllers[state.id] = controller
        controller.show()
    }

    func toggleAll() {
        let all = Array(controllers.values)
        guard !all.isEmpty else { return }
        let allVisible = all.allSatisfy { $0.isVisible }
        all.forEach { allVisible ? $0.hide() : $0.show() }
    }
}
