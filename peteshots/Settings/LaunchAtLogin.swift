//
//  LaunchAtLogin.swift
//  peteshots
//

import Foundation
import OSLog
import ServiceManagement

/// Wraps `SMAppService.mainApp` (spec §9).
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.peteshots.peteshots", category: "settings")

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The default is on. Registers once, the first time the app runs.
    /// Afterwards the Settings toggle is the source of truth.
    static func registerOnFirstLaunch(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: AppSettings.Key.launchAtLogin) == nil else { return }
        setEnabled(true)
        defaults.set(true, forKey: AppSettings.Key.launchAtLogin)
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "Peteshots opens when you log in."
        case .requiresApproval: "Needs approval in System Settings → Login Items."
        case .notRegistered: "Off."
        case .notFound: "Not available. Install Peteshots in /Applications."
        @unknown default: "Unknown status."
        }
    }
}
