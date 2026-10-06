//
//  BackgroundDrawing.swift
//  peteshots
//

import CoreGraphics

/// Shared background drawing for the canvas and the export (spec §5.6b). The
/// context is set up in image pixels with a top-left origin.
nonisolated enum BackgroundDrawing {
    /// Draws the gradient over the padded area and the screenshot's shadow,
    /// then calls `content` clipped to the crop with rounded corners.
    static func draw(_ background: Background, crop: CGRect, in context: CGContext, content: () -> Void) {
        let crop = crop.standardized
        drawGradient(background.gradient, in: background.canvasRect(for: crop), context: context)

        let radius = Background.cornerRadius(for: crop)
        let screenshot = CGPath(roundedRect: crop, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Shadows ignore the context transform, so the blur and offset are
        // scaled to device pixels. The canvas and the export then match.
        let transform = context.userSpaceToDeviceSpaceTransform
        let deviceScale = hypot(transform.a, transform.b)
        let blur = Background.shadowBlur(for: crop) * deviceScale
        context.saveGState()
        // Device space has a bottom-left origin, so a negative offset moves the shadow down.
        context.setShadow(offset: CGSize(width: 0, height: -blur * 0.3), blur: blur, color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(screenshot)
        context.setFillColor(gray: 0, alpha: 1)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(screenshot)
        context.clip()
        content()
        context.restoreGState()
    }

    /// A diagonal linear gradient from the top-left corner to the bottom-right.
    static func drawGradient(_ gradient: BackgroundGradient, in rect: CGRect, context: CGContext) {
        let colors = gradient.colorHexes.map(HexColor.cgColor(from:))
        let count = colors.count
        let locations = (0..<count).map { CGFloat($0) / CGFloat(max(count - 1, 1)) }
        guard let cgGradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: locations
        ) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            cgGradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }
}
