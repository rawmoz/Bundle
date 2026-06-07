import SwiftUI

@main
struct BundleApp: App {
    @State private var manager = BundleManager()

    var body: some Scene {
        MenuBarExtra("Bundle", systemImage: "square.stack.3d.up") {
            MenuBarView(manager: manager)
        }
        .menuBarExtraStyle(.window)
    }
}
