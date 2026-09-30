//
//  TextLayout.swift
//  peteshots
//

import AppKit

/// Text attributes and measuring shared by the canvas, the inline editor, and
/// the export (spec §5.6). Sizes are in the caller's units: image pixels for
/// the canvas and export, view points for the inline editor.
nonisolated enum TextLayout {
    /// Line height as a multiple of the font size. Every line has exactly this
    /// height, so `fontSize = boxHeight / lineCount / lineHeightMultiple` holds.
    static let lineHeightMultiple: CGFloat = 1.2
    /// Shadow blur in image pixels (spec §5.6).
    static let shadowBlurRadius: CGFloat = 1
    /// The smallest font size a resize can reach, in image px.
    static let minFontSize: CGFloat = 6
    /// Wider than any line, so drawing never wraps. Lines only break at Return.
    static let unlimitedWidth: CGFloat = 100_000

    static func font(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    /// The text attributes. `shadowBlur` is in device pixels, because shadows
    /// ignore the context transform.
    static func attributes(fontSize: CGFloat, colorHex: String, shadowBlur: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = fontSize * lineHeightMultiple
        paragraph.maximumLineHeight = fontSize * lineHeightMultiple
        paragraph.lineBreakMode = .byClipping

        let shadow = NSShadow()
        shadow.shadowBlurRadius = shadowBlur
        shadow.shadowOffset = .zero
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)

        return [
            .font: font(size: fontSize),
            .foregroundColor: NSColor(cgColor: HexColor.cgColor(from: colorHex)) ?? .red,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ]
    }

    /// Lines break only at Return, so the count is the number of newlines plus one.
    static func lineCount(of string: String) -> Int {
        string.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
    }

    /// The box size in image px: the widest line by the fixed line height.
    static func size(of text: TextAnnotation) -> CGSize {
        let attributed = NSAttributedString(
            string: text.string,
            attributes: attributes(fontSize: text.fontSize, colorHex: text.colorHex, shadowBlur: 0)
        )
        let measured = attributed.boundingRect(
            with: CGSize(width: unlimitedWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        let lineHeight = text.fontSize * lineHeightMultiple
        return CGSize(width: max(measured.width, 1), height: CGFloat(lineCount(of: text.string)) * lineHeight)
    }

    /// The box in image px, with the top-left at `origin`.
    static func frame(of text: TextAnnotation) -> CGRect {
        CGRect(origin: text.origin, size: size(of: text))
    }

    /// Scales the text by dragging `corner` to `point` while the opposite
    /// corner stays fixed (spec §5.6). The width follows the new font size.
    static func resize(_ text: TextAnnotation, corner: Geometry.RectHandle, to point: CGPoint) -> TextAnnotation {
        let frame = frame(of: text)
        let anchor = corner.opposite.point(in: frame)
        // Distances from the fixed corner, positive toward the dragged corner.
        let dx = (point.x - anchor.x) * (corner.movesMaxX ? 1 : -1)
        let dy = (point.y - anchor.y) * (corner.movesMaxY ? 1 : -1)
        let scale = max(dx / frame.width, dy / frame.height)
        let boxHeight = frame.height * scale

        var resized = text
        resized.fontSize = max(minFontSize, boxHeight / CGFloat(lineCount(of: text.string)) / lineHeightMultiple)
        let size = size(of: resized)
        resized.origin = CGPoint(
            x: corner.movesMaxX ? anchor.x : anchor.x - size.width,
            y: corner.movesMaxY ? anchor.y : anchor.y - size.height
        )
        return resized
    }
}
