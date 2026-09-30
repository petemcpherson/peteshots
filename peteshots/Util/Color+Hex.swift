//
//  Color+Hex.swift
//  peteshots
//

import AppKit
import SwiftUI

/// Converts between `#RRGGBB` strings and colors. Hex values are sRGB.
nonisolated enum HexColor {
    struct RGB: Equatable, Sendable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
    }

    /// Parses `#RRGGBB` or `RRGGBB`. Returns nil for anything else.
    static func rgb(from hex: String) -> RGB? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return RGB(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255
        )
    }

    /// Formats components (0–1, sRGB) as `#RRGGBB`.
    static func hex(from rgb: RGB) -> String {
        func byte(_ component: CGFloat) -> Int {
            Int((Geometry.clamp(component, 0, 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(rgb.red), byte(rgb.green), byte(rgb.blue))
    }

    /// The color for drawing. An invalid hex falls back to the default red.
    static func cgColor(from hex: String) -> CGColor {
        let rgb = rgb(from: hex) ?? rgb(from: AppSettings.Default.annotationColorHex)!
        return CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

extension NSColor {
    /// The color as `#RRGGBB` in sRGB. Nil if it has no sRGB form (for example, a pattern).
    var hexString: String? {
        guard let srgb = usingColorSpace(.sRGB) else { return nil }
        return HexColor.hex(from: .init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent))
    }
}

extension Color {
    init(hex: String) {
        self.init(cgColor: HexColor.cgColor(from: hex))
    }

    var hexString: String? {
        NSColor(self).hexString
    }
}
