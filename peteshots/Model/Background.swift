//
//  Background.swift
//  peteshots
//

import CoreGraphics
import Foundation

/// A built-in gradient drawn behind the screenshot (spec §5.6b). No custom gradients.
nonisolated enum BackgroundGradient: String, CaseIterable, Sendable {
    case sunset, ocean, grape, aurora, mint, peach, cloud, midnight

    var title: String {
        switch self {
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .grape: "Grape"
        case .aurora: "Aurora"
        case .mint: "Mint"
        case .peach: "Peach"
        case .cloud: "Cloud"
        case .midnight: "Midnight"
        }
    }

    /// Color stops as sRGB hex, evenly spaced from the top-left corner to the bottom-right.
    var colorHexes: [String] {
        switch self {
        case .sunset: ["#FF5F8F", "#FF9A5A"]
        case .ocean: ["#2B5DE8", "#3FC8F0"]
        case .grape: ["#4A2BD8", "#B24BF3"]
        case .aurora: ["#F7A65C", "#C25BD9", "#4A6CF0"]
        case .mint: ["#3BC9A8", "#A6E7C9"]
        case .peach: ["#F6D365", "#FD8A6B"]
        case .cloud: ["#F7F8FA", "#D9DEE6"]
        case .midnight: ["#2A2D33", "#111215"]
        }
    }
}

/// The gradient background and how much of it shows around the screenshot.
nonisolated struct Background: Equatable, Sendable {
    var gradient: BackgroundGradient
    /// Padding on each side, as a fraction of the crop's long side.
    var padding: CGFloat

    static let paddingRange: ClosedRange<CGFloat> = 0.02...0.2
    static let defaultPadding: CGFloat = 0.08

    /// Padding on each side in image px for the given crop, rounded to whole pixels.
    func paddingPixels(for crop: CGRect) -> CGFloat {
        let crop = crop.standardized
        return (padding * max(crop.width, crop.height)).rounded()
    }

    /// The whole output area in image px: the crop with padding on each side.
    func canvasRect(for crop: CGRect) -> CGRect {
        let pad = paddingPixels(for: crop)
        return crop.standardized.insetBy(dx: -pad, dy: -pad)
    }

    /// Corner radius of the screenshot: 1.2% of the crop's long side, clamped to 6–24 px.
    static func cornerRadius(for crop: CGRect) -> CGFloat {
        Geometry.clamp(0.012 * max(crop.width, crop.height), 6, 24)
    }

    /// Shadow blur under the screenshot: 2% of the crop's long side, clamped to 8–40 px.
    static func shadowBlur(for crop: CGRect) -> CGFloat {
        Geometry.clamp(0.02 * max(crop.width, crop.height), 8, 40)
    }
}
