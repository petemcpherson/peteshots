//
//  Renderer.swift
//  peteshots
//

import CoreGraphics

/// Flattens the base image and the annotations into one image (spec §7.1).
nonisolated enum Renderer {
    /// An 8-bit sRGB context with no alpha, flipped so drawing uses image
    /// pixels with a top-left origin.
    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        return context
    }

    /// The crop area of `base` with every annotation drawn on it, through the
    /// same drawing code as the canvas. Annotations outside the crop are clipped.
    static func flatten(base: CGImage, document: EditorDocument) -> CGImage? {
        let crop = document.cropRect.standardized
        let width = Int(crop.width.rounded())
        let height = Int(crop.height.rounded())
        guard let context = makeContext(width: width, height: height) else { return nil }

        context.interpolationQuality = .high
        context.translateBy(x: -crop.minX, y: -crop.minY)
        context.clip(to: crop)

        let imageHeight = CGFloat(base.height)
        context.saveGState()
        // CGContext.draw expects a bottom-left origin; flip locally so the image is upright.
        context.translateBy(x: 0, y: imageHeight)
        context.scaleBy(x: 1, y: -1)
        context.draw(base, in: CGRect(x: 0, y: 0, width: CGFloat(base.width), height: imageHeight))
        context.restoreGState()

        AnnotationDrawing.draw(document.annotations, base: base, in: context)
        return context.makeImage()
    }
}
