//
//  BlurRenderer.swift
//  peteshots
//

import CoreImage
import os

/// Renders blurred regions of the base image (spec §5.5). One shared
/// `CIContext`, and a small cache so an unchanged redraw does not blur again.
nonisolated final class BlurRenderer: Sendable {
    static let shared = BlurRenderer()

    static let minRadius: CGFloat = 12
    static let maxRadius: CGFloat = 40

    private struct Entry {
        let base: CGImage
        let rect: CGRect
        let radius: CGFloat
        let image: CGImage
    }

    private static let cacheLimit = 32

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let cache = OSAllocatedUnfairLock<[Entry]>(initialState: [])

    /// Blur radius in px for a region: a quarter of its short side, clamped.
    static func radius(for rect: CGRect) -> CGFloat {
        let rect = rect.standardized
        return Geometry.clamp(min(rect.width, rect.height) * 0.25, minRadius, maxRadius)
    }

    /// The area actually rendered for `rect`: whole pixels inside the image.
    static func renderRect(for rect: CGRect, imageSize: CGSize) -> CGRect {
        rect.standardized.integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// The blurred pixels of `base` under `rect` (image px, top-left origin),
    /// upright, sized to `renderRect(for:imageSize:)`. Nil if the rect is off the image.
    func blurredImage(of base: CGImage, in rect: CGRect) -> CGImage? {
        let imageSize = CGSize(width: base.width, height: base.height)
        let target = Self.renderRect(for: rect, imageSize: imageSize)
        guard !target.isNull, target.width >= 1, target.height >= 1 else { return nil }
        let radius = Self.radius(for: rect)

        if let hit = cache.withLock({ $0.first { $0.base === base && $0.rect == target && $0.radius == radius } }) {
            return hit.image
        }

        // Core Image uses a bottom-left origin.
        let ciRect = CGRect(x: target.minX, y: imageSize.height - target.maxY, width: target.width, height: target.height)
        let blurred = CIImage(cgImage: base)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: ciRect)
        let colorSpace = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let image = context.createCGImage(blurred, from: ciRect, format: .RGBA8, colorSpace: colorSpace) else {
            return nil
        }

        cache.withLock { entries in
            entries.append(Entry(base: base, rect: target, radius: radius, image: image))
            if entries.count > Self.cacheLimit { entries.removeFirst(entries.count - Self.cacheLimit) }
        }
        return image
    }
}
