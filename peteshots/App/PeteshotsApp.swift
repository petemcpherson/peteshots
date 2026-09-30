//
//  PeteshotsApp.swift
//  peteshots
//

import SwiftUI

@main
struct PeteshotsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Peteshots", systemImage: "camera.viewfinder") {
            MenuContent()
        }

        Settings {
            SettingsView()
        }
    }
}
