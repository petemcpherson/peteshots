//
//  EditorDocument.swift
//  peteshots
//

import CoreGraphics
import Foundation

/// The whole editable state of one capture (spec §5.9). All geometry is in
/// image pixel space with a top-left origin.
nonisolated struct EditorDocument: Equatable, Sendable {
    var annotations: [Annotation]
    var cropRect: CGRect

    init(imageSize: CGSize) {
        annotations = []
        cropRect = CGRect(origin: .zero, size: imageSize)
    }

    func annotation(withID id: Annotation.ID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    mutating func updateAnnotation(withID id: Annotation.ID, _ change: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        change(&annotations[index])
    }

    mutating func removeAnnotation(withID id: Annotation.ID) {
        annotations.removeAll { $0.id == id }
    }
}

nonisolated struct ArrowAnnotation: Equatable, Sendable {
    var id = UUID()
    var start: CGPoint
    var end: CGPoint
    var colorHex: String
    var strokeWidth: CGFloat
}

nonisolated struct BlurAnnotation: Equatable, Sendable {
    var id = UUID()
    var rect: CGRect
}

nonisolated struct TextAnnotation: Equatable, Sendable {
    var id = UUID()
    /// Top-left corner of the text box.
    var origin: CGPoint
    var string: String
    var fontSize: CGFloat
    var colorHex: String
}

nonisolated enum Annotation: Equatable, Sendable, Identifiable {
    case arrow(ArrowAnnotation)
    case blur(BlurAnnotation)
    case text(TextAnnotation)

    var id: UUID {
        switch self {
        case .arrow(let arrow): arrow.id
        case .blur(let blur): blur.id
        case .text(let text): text.id
        }
    }

    var isBlur: Bool {
        if case .blur = self { true } else { false }
    }

    /// Arrows and text use the annotation color. Blur does not (spec §5.3).
    var colorHex: String? {
        switch self {
        case .arrow(let arrow): arrow.colorHex
        case .blur: nil
        case .text(let text): text.colorHex
        }
    }

    /// The annotation with a new color. A blur is returned unchanged.
    func withColor(_ hex: String) -> Annotation {
        switch self {
        case .arrow(var arrow):
            arrow.colorHex = hex
            return .arrow(arrow)
        case .blur:
            return self
        case .text(var text):
            text.colorHex = hex
            return .text(text)
        }
    }

    /// Moves the whole annotation by the given offset in image pixels.
    func offsetBy(dx: CGFloat, dy: CGFloat) -> Annotation {
        switch self {
        case .arrow(var arrow):
            arrow.start = CGPoint(x: arrow.start.x + dx, y: arrow.start.y + dy)
            arrow.end = CGPoint(x: arrow.end.x + dx, y: arrow.end.y + dy)
            return .arrow(arrow)
        case .blur(var blur):
            blur.rect = blur.rect.offsetBy(dx: dx, dy: dy)
            return .blur(blur)
        case .text(var text):
            text.origin = CGPoint(x: text.origin.x + dx, y: text.origin.y + dy)
            return .text(text)
        }
    }

    /// True when the point (image px) is on the annotation, within `tolerance` px.
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch self {
        case .arrow(let arrow):
            Geometry.distance(from: point, toSegment: arrow.start, arrow.end) <= tolerance + arrow.strokeWidth / 2
        case .blur(let blur):
            blur.rect.standardized.contains(point)
        case .text(let text):
            TextLayout.frame(of: text).insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point)
        }
    }

    /// Handle positions (image px) shown when the annotation is selected.
    var handlePoints: [CGPoint] {
        switch self {
        case .arrow(let arrow):
            [arrow.start, arrow.end]
        case .blur(let blur):
            Geometry.RectHandle.allCases.map { $0.point(in: blur.rect.standardized) }
        case .text(let text):
            Geometry.RectHandle.corners.map { $0.point(in: TextLayout.frame(of: text)) }
        }
    }
}
