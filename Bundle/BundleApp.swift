//
//  BundleApp.swift
//  Bundle
//
//  Created by Daniel Ramos on 5/21/26.
//

import SwiftUI

@main
struct BundleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
