import SwiftUI

@main
struct BundleApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Bundle", systemImage: "square.stack.3d.up") {
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
