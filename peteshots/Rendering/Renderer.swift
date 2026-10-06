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
    /// With a background, the output adds its padding on each side (spec §5.6b).
    static func flatten(base: CGImage, document: EditorDocument) -> CGImage? {
        let crop = document.cropRect.standardized
        let output = document.background?.canvasRect(for: crop) ?? crop
        let width = Int(output.width.rounded())
        let height = Int(output.height.rounded())
        guard let context = makeContext(width: width, height: height) else { return nil }

        context.interpolationQuality = .high
        context.translateBy(x: -output.minX, y: -output.minY)
        if let background = document.background {
            BackgroundDrawing.draw(background, crop: crop, in: context) {
                drawContent(base: base, annotations: document.annotations, in: context)
            }
        } else {
            context.clip(to: crop)
            drawContent(base: base, annotations: document.annotations, in: context)
        }
        return context.makeImage()
    }

    /// The base image and annotations, in image pixels.
    private static func drawContent(base: CGImage, annotations: [Annotation], in context: CGContext) {
        let imageHeight = CGFloat(base.height)
        context.saveGState()
        // CGContext.draw expects a bottom-left origin; flip locally so the image is upright.
        context.translateBy(x: 0, y: imageHeight)
        context.scaleBy(x: 1, y: -1)
        context.draw(base, in: CGRect(x: 0, y: 0, width: CGFloat(base.width), height: imageHeight))
        context.restoreGState()

        AnnotationDrawing.draw(annotations, base: base, in: context)
    }
}
