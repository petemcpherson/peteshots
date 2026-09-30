//
//  CoordinateSpace.swift
//  peteshots
//

import AppKit

nonisolated enum CoordinateSpace {
    /// Converts a rect from Cocoa global space (bottom-left origin, primary screen)
    /// to CG display space (top-left origin, primary screen).
    static func cgRect(fromCocoa rect: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Same conversion, using the live primary screen (`NSScreen.screens[0]`).
    @MainActor
    static func cgRect(fromCocoa rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first?.frame ?? .zero
        return cgRect(fromCocoa: rect, primaryScreenFrame: primary)
    }
}
