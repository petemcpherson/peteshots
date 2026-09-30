//
//  AnnotationDrawing.swift
//  peteshots
//

import CoreGraphics

/// Shared annotation drawing for the canvas and the export (spec §7.1). Every
/// function takes a context set up in image pixels with a top-left origin.
nonisolated enum AnnotationDrawing {
    /// Draws all annotations: blurs first, then arrows and text, each in
    /// creation order (spec §5.8).
    static func draw(_ annotations: [Annotation], base: CGImage, in context: CGContext) {
        for case .blur(let blur) in annotations {
            drawBlur(blur, base: base, in: context)
        }
        for annotation in annotations {
            switch annotation {
            case .arrow(let arrow): drawArrow(arrow, in: context)
            case .blur: break
            case .text: break // Text drawing arrives with the text tool (Phase 5).
            }
        }
    }

    // MARK: - Arrow

    /// Head length and width as multiples of the stroke width.
    static let headLengthFactor: CGFloat = 4
    static let headWidthFactor: CGFloat = 3.5

    static func drawArrow(_ arrow: ArrowAnnotation, in context: CGContext) {
        let dx = arrow.end.x - arrow.start.x
        let dy = arrow.end.y - arrow.start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }

        let unit = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let width = arrow.strokeWidth
        // A short arrow keeps its head shape and shrinks it to fit.
        let headLength = min(width * headLengthFactor, length)
        let halfHead = headLength * headWidthFactor / headLengthFactor / 2
        let base = CGPoint(x: arrow.end.x - unit.x * headLength, y: arrow.end.y - unit.y * headLength)

        context.saveGState()
        let color = HexColor.cgColor(from: arrow.colorHex)
        context.setStrokeColor(color)
        context.setFillColor(color)

        // The line ends at the head base. Its round cap hides under the head.
        if length > headLength {
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.move(to: arrow.start)
            context.addLine(to: base)
            context.strokePath()
        }

        context.move(to: arrow.end)
        context.addLine(to: CGPoint(x: base.x + normal.x * halfHead, y: base.y + normal.y * halfHead))
        context.addLine(to: CGPoint(x: base.x - normal.x * halfHead, y: base.y - normal.y * halfHead))
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Blur

    static func drawBlur(_ blur: BlurAnnotation, base: CGImage, in context: CGContext) {
        let imageSize = CGSize(width: base.width, height: base.height)
        guard let image = BlurRenderer.shared.blurredImage(of: base, in: blur.rect) else { return }
        let target = BlurRenderer.renderRect(for: blur.rect, imageSize: imageSize)

        context.saveGState()
        // CGContext.draw expects a bottom-left origin; flip locally so the image is upright.
        context.translateBy(x: 0, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: target.minX, y: 0, width: target.width, height: target.height))
        context.restoreGState()
    }
}
