import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: ShelfWindowController?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let wc = ShelfWindowController()
        windowController = wc
        hotkeyManager = HotkeyManager { wc.toggle() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
