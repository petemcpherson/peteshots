//
//  AnnotationDrawing.swift
//  peteshots
//

import AppKit

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
            case .text(let text): drawText(text, in: context)
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

        let wing = CGPoint(x: normal.x * halfHead, y: normal.y * halfHead)
        let head = [arrow.end, CGPoint(x: base.x + wing.x, y: base.y + wing.y), CGPoint(x: base.x - wing.x, y: base.y - wing.y)]

        /// Draws the arrow shape grown by `pad` on every side.
        func drawShape(_ colorHex: String, pad: CGFloat) {
            let color = HexColor.cgColor(from: colorHex)
            context.setStrokeColor(color)
            context.setFillColor(color)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            // The line ends at the head base. Its round cap hides under the head.
            if length > headLength {
                context.setLineWidth(width + 2 * pad)
                context.move(to: arrow.start)
                context.addLine(to: base)
                context.strokePath()
            }

            context.addLines(between: head)
            context.closePath()
            if pad > 0 {
                context.setLineWidth(2 * pad)
                context.drawPath(using: .fillStroke)
            } else {
                context.fillPath()
            }
        }

        context.saveGState()
        let pad = width * arrow.outline.width.arrowFraction
        if pad > 0 {
            drawShape(arrow.outline.colorHex, pad: pad)
        }
        drawShape(arrow.colorHex, pad: 0)
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

    // MARK: - Text

    /// Draws the text. With `outlineOnly`, draws just the outline, for text
    /// whose fill the inline editor shows.
    static func drawText(_ text: TextAnnotation, outlineOnly: Bool = false, in context: CGContext) {
        // Shadows ignore the context transform, so the blur is scaled to device
        // pixels here. The canvas and the export then show the same shadow.
        let transform = context.userSpaceToDeviceSpaceTransform
        let deviceScale = hypot(transform.a, transform.b)
        let shadowBlur = TextLayout.shadowBlurRadius * deviceScale
        let hasOutline = text.outline.width != .off
        guard hasOutline || !outlineOnly else { return }

        let height = CGFloat(TextLayout.lineCount(of: text.string)) * text.fontSize * TextLayout.lineHeightMultiple
        let rect = CGRect(x: text.origin.x, y: text.origin.y, width: TextLayout.unlimitedWidth, height: height)

        context.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        // Round joins keep thick outlines from spiking at sharp glyph corners.
        context.setLineJoin(.round)
        if hasOutline {
            // The outline carries the shadow, so the fill drawn over it has none.
            NSAttributedString(
                string: text.string,
                attributes: TextLayout.outlineAttributes(fontSize: text.fontSize, outline: text.outline, shadowBlur: shadowBlur)
            ).draw(with: rect, options: [.usesLineFragmentOrigin])
        }
        if !outlineOnly {
            NSAttributedString(
                string: text.string,
                attributes: TextLayout.attributes(fontSize: text.fontSize, colorHex: text.colorHex, shadowBlur: hasOutline ? 0 : shadowBlur)
            ).draw(with: rect, options: [.usesLineFragmentOrigin])
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}
