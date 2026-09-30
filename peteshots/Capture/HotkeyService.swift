//
//  HotkeyService.swift
//  peteshots
//

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let takeScreenshot = Self("takeScreenshot", default: .init(.a, modifiers: [.command, .shift]))
}

enum HotkeyService {
    /// Registers the global capture hotkey. Call once at launch.
    static func register() {
        KeyboardShortcuts.onKeyDown(for: .takeScreenshot) {
            CaptureCoordinator.shared.start()
        }
    }
}
