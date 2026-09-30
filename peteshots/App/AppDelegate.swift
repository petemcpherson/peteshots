//
//  AppDelegate.swift
//  peteshots
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        HotkeyService.register()
        LaunchAtLogin.registerOnFirstLaunch()
    }
}
