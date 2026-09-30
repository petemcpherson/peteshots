//
//  PermissionWindow.swift
//  peteshots
//

import AppKit
import SwiftUI

/// Small window that explains why Screen Recording access is needed.
final class PermissionWindow {
    static let shared = PermissionWindow()

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screen Recording Permission"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PermissionView {
            NSWorkspace.shared.open(Self.settingsURL)
            window.close()
        })
        return window
    }
}

private struct PermissionView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Peteshots needs Screen Recording access")
                .font(.headline)
            Text("To capture screenshots, turn on Peteshots in System Settings → Privacy & Security → Screen & System Audio Recording. You may need to quit and reopen Peteshots afterwards.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Open System Settings", action: openSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
