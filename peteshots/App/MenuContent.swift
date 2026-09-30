//
//  MenuContent.swift
//  peteshots
//

import KeyboardShortcuts
import SwiftUI

struct MenuContent: View {
    var body: some View {
        Button("Take Screenshot") {
            CaptureCoordinator.shared.start()
        }
        .globalKeyboardShortcut(.takeScreenshot)

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
