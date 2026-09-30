//
//  PermissionService.swift
//  peteshots
//

import CoreGraphics

enum PermissionService {
    /// Returns true if the app can capture the screen. If not, asks the system
    /// for access and shows the explanation window (spec §4.2).
    static func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        CGRequestScreenCaptureAccess()
        PermissionWindow.shared.show()
        return false
    }
}
