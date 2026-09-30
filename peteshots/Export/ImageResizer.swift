//
//  ImageResizer.swift
//  peteshots
//

import CoreImage

/// Scales large images down so the long side fits the limit (spec §7.2).
nonisolated enum ImageResizer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The output size in whole pixels, or nil when no resize is needed.
    /// Never scales up.
    static func targetSize(width: Int, height: Int, maxLongSide: Int) -> (width: Int, height: Int)? {
        let longSide = max(width, height)
        guard maxLongSide > 0, longSide > maxLongSide else { return nil }
        let scale = Double(maxLongSide) / Double(longSide)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }

    /// `image` scaled to exactly `width` × `height` with Lanczos resampling,
    /// in 8-bit sRGB with no alpha.
    static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let scaleY = CGFloat(height) / CGFloat(image.height)
        let scaleX = CGFloat(width) / CGFloat(image.width)
        let target = CGRect(x: 0, y: 0, width: width, height: height)

        // Clamping keeps the edges from fading into transparent pixels.
        let scaled = CIImage(cgImage: image)
            .clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scaleY,
                kCIInputAspectRatioKey: scaleX / scaleY,
            ])
            .cropped(to: target)

        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let rendered = context.createCGImage(scaled, from: target, format: .RGBA8, colorSpace: sRGB),
              let output = Renderer.makeContext(width: width, height: height)
        else { return nil }

        // Redraw into a context with no alpha channel (spec §7.3). Undo the
        // flip so the image lands upright.
        output.scaleBy(x: 1, y: -1)
        output.translateBy(x: 0, y: -CGFloat(height))
        output.draw(rendered, in: target)
        return output.makeImage()
    }
}
