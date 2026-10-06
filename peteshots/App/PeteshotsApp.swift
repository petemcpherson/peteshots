//
//  PeteshotsApp.swift
//  peteshots
//

import SwiftUI

@main
struct PeteshotsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }

        Settings {
            SettingsView()
        }
    }
}
