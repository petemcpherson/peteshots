//
//  MenuContent.swift
//  peteshots
//

import KeyboardShortcuts
import SwiftUI

struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Take Screenshot") {
            CaptureCoordinator.shared.start()
        }
        .globalKeyboardShortcut(.takeScreenshot)

        Button("Open Destination Folder") {
            NSWorkspace.shared.open(AppSettings.destinationURL)
        }

        Button("Settings…") {
            // A menu bar app must activate, or the window opens behind others.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Peteshots") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
