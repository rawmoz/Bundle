import Foundation

// Temporary coordinator for v0.1 — replaced by BundleManager in v0.2
@Observable
final class AppCoordinator {
    private let panels: [BundlePanelController]
    private let hotkeyManager = HotkeyManager()

    init() {
        let panel = BundlePanelController(columns: 1, rows: 3)
        panels = [panel]
        panel.show()

        hotkeyManager.onToggle = { [weak self] in
            guard let self else { return }
            let allVisible = panels.allSatisfy { $0.isVisible }
            panels.forEach { allVisible ? $0.hide() : $0.show() }
        }
        hotkeyManager.register()
    }
}
