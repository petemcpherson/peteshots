//
//  MenuContent.swift
//  peteshots
//

import SwiftUI

struct MenuContent: View {
    var body: some View {
        Button("Take Screenshot") {
            // Connected to the capture flow in Phase 2.
        }

        Button("Open Destination Folder") {
            NSWorkspace.shared.open(AppSettings.destinationURL)
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Peteshots") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
