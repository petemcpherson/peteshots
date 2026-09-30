//
//  CanvasView.swift
//  peteshots
//

import AppKit
import Observation

/// Draws the image and annotations and handles mouse input. Flipped, so view
/// coordinates run top-left like image space.
final class CanvasView: NSView {
    static let handleSize: CGFloat = 8
    /// Hit-test tolerance in view points (spec §5.4).
    static let hitTolerance: CGFloat = 8

    /// Drags shorter than this (view points) do not create an arrow.
    static let minArrowDrag: CGFloat = 4

    /// What the current mouse drag does. Points are in image px.
    private enum Drag {
        /// Moves a whole annotation. `last` is the previous drag point.
        case move(id: Annotation.ID, last: CGPoint)
        /// Moves one end of an arrow.
        case arrowEnd(id: Annotation.ID, isStart: Bool)
        /// Resizes a blur by one of its 8 handles.
        case blurResize(id: Annotation.ID, handle: Geometry.RectHandle)
        /// Creates a new annotation with the arrow or blur tool.
        case create(tool: Tool, start: CGPoint)
    }

    private let state: EditorState
    private var drag: Drag?
    /// The annotation being created, drawn on top until mouse-up.
    private var draft: Annotation? {
        didSet { needsDisplay = true }
    }

    init(state: EditorState) {
        self.state = state
        super.init(frame: .zero)
        observeState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    private func observeState() {
        withObservationTracking {
            _ = state.document
            _ = state.selectedID
            _ = state.tool
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
                self.observeState()
            }
        }
    }

    override func resetCursorRects() {
        switch state.tool {
        case .arrow, .blur, .crop: addCursorRect(bounds, cursor: .crosshair)
        case .text: addCursorRect(bounds, cursor: .iBeam)
        case .select: break
        }
    }

    // MARK: - Transform

    /// The image area shown: the full image in crop mode, otherwise the crop rect.
    private var visibleImageRect: CGRect {
        state.tool == .crop ? state.imageBounds : state.document.cropRect
    }

    /// View points per image pixel. Never larger than 1:1 on the capture screen.
    private var fitScale: CGFloat {
        let visible = visibleImageRect
        guard visible.width > 0, visible.height > 0 else { return 1 }
        return min(state.pointsPerPixel, bounds.width / visible.width, bounds.height / visible.height)
    }

    /// Top-left of the visible image area in view points (centered).
    private var imageOffset: CGPoint {
        let visible = visibleImageRect
        let scale = fitScale
        return CGPoint(
            x: ((bounds.width - visible.width * scale) / 2).rounded(),
            y: ((bounds.height - visible.height * scale) / 2).rounded()
        )
    }

    func imageToView(_ point: CGPoint) -> CGPoint {
        let visible = visibleImageRect
        let scale = fitScale
        let offset = imageOffset
        return CGPoint(
            x: (point.x - visible.minX) * scale + offset.x,
            y: (point.y - visible.minY) * scale + offset.y
        )
    }

    func viewToImage(_ point: CGPoint) -> CGPoint {
        let visible = visibleImageRect
        let scale = fitScale
        let offset = imageOffset
        return CGPoint(
            x: (point.x - offset.x) / scale + visible.minX,
            y: (point.y - offset.y) / scale + visible.minY
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let visible = visibleImageRect
        let scale = fitScale
        let offset = imageOffset

        context.saveGState()
        context.translateBy(x: offset.x, y: offset.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -visible.minX, y: -visible.minY)
        // From here on, drawing uses image pixels with a top-left origin.
        context.clip(to: visible)
        context.interpolationQuality = .high
        drawBaseImage(in: context)
        AnnotationDrawing.draw(state.document.annotations, base: state.baseImage, in: context)
        if let draft {
            AnnotationDrawing.draw([draft], base: state.baseImage, in: context)
        }
        context.restoreGState()

        if case .blur(let blur)? = draft {
            strokeOutline(of: blur.rect)
        }

        drawSelectionHandles()
    }

    private func drawBaseImage(in context: CGContext) {
        let image = state.baseImage
        let height = CGFloat(image.height)
        context.saveGState()
        // CGContext.draw expects a bottom-left origin; flip locally so the image is upright.
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: height))
        context.restoreGState()
    }

    /// Handles draw in view space at a fixed size, so they stay usable at any scale.
    private func drawSelectionHandles() {
        guard let annotation = state.selectedAnnotation else { return }
        if case .blur(let blur) = annotation {
            strokeOutline(of: blur.rect)
        }
        let size = Self.handleSize
        for point in annotation.handlePoints {
            let center = imageToView(point)
            let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            let path = NSBezierPath(ovalIn: rect)
            NSColor.white.setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    /// A thin outline around a blur region (image px), drawn in view space.
    private func strokeOutline(of rect: CGRect) {
        let rect = rect.standardized
        let topLeft = imageToView(rect.origin)
        let bottomRight = imageToView(CGPoint(x: rect.maxX, y: rect.maxY))
        let path = NSBezierPath(rect: Geometry.rect(from: topLeft, to: bottomRight).insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = viewToImage(convert(event.locationInWindow, from: nil))

        switch state.tool {
        case .select:
            beginSelectDrag(at: point)
        case .arrow, .blur:
            drag = .create(tool: state.tool, start: Geometry.clampPoint(point, to: state.imageBounds))
        case .text, .crop:
            // Tool input arrives in Phase 5.
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = viewToImage(convert(event.locationInWindow, from: nil))

        switch drag {
        case .move(let id, let last):
            let dx = point.x - last.x
            let dy = point.y - last.y
            state.updateLive { document in
                document.updateAnnotation(withID: id) { $0 = $0.offsetBy(dx: dx, dy: dy) }
            }
            self.drag = .move(id: id, last: point)

        case .arrowEnd(let id, let isStart):
            state.updateLive { document in
                document.updateAnnotation(withID: id) { annotation in
                    guard case .arrow(var arrow) = annotation else { return }
                    if isStart { arrow.start = point } else { arrow.end = point }
                    annotation = .arrow(arrow)
                }
            }

        case .blurResize(let id, let handle):
            state.updateLive { document in
                document.updateAnnotation(withID: id) { annotation in
                    guard case .blur(var blur) = annotation else { return }
                    blur.rect = Geometry.resize(blur.rect.standardized, handle: handle, to: point, minSize: EditorState.minBlurSize)
                    annotation = .blur(blur)
                }
            }

        case .create(let tool, let start):
            draft = makeDraft(tool: tool, from: start, to: Geometry.clampPoint(point, to: state.imageBounds))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil

        switch drag {
        case .move, .arrowEnd, .blurResize:
            state.endLiveChange()
        case .create:
            if let draft, isLargeEnough(draft) {
                state.place(draft)
            }
            draft = nil
        }
    }

    private func beginSelectDrag(at point: CGPoint) {
        if let handleDrag = handleDrag(at: point) {
            state.beginLiveChange()
            drag = handleDrag
            return
        }
        guard let annotation = hitTest(imagePoint: point) else {
            state.selectedID = nil
            return
        }
        state.selectedID = annotation.id
        state.beginLiveChange()
        drag = .move(id: annotation.id, last: point)
    }

    /// A drag on one of the selected annotation's handles, if the point is on one.
    private func handleDrag(at point: CGPoint) -> Drag? {
        guard let annotation = state.selectedAnnotation else { return nil }
        let radius = Self.handleSize / fitScale
        switch annotation {
        case .arrow(let arrow):
            // The end wins when both handles overlap, so a short arrow can grow.
            if Geometry.distance(point, arrow.end) <= radius {
                return .arrowEnd(id: arrow.id, isStart: false)
            }
            if Geometry.distance(point, arrow.start) <= radius {
                return .arrowEnd(id: arrow.id, isStart: true)
            }
            return nil
        case .blur(let blur):
            return Geometry.handle(at: point, in: blur.rect.standardized, radius: radius)
                .map { .blurResize(id: blur.id, handle: $0) }
        case .text:
            return nil
        }
    }

    private func makeDraft(tool: Tool, from start: CGPoint, to end: CGPoint) -> Annotation? {
        switch tool {
        case .arrow:
            .arrow(ArrowAnnotation(start: start, end: end, colorHex: state.colorHex, strokeWidth: state.arrowStrokeWidth))
        case .blur:
            .blur(BlurAnnotation(rect: Geometry.rect(from: start, to: end)))
        case .select, .text, .crop:
            nil
        }
    }

    /// Tiny drags are ignored instead of placing an annotation.
    private func isLargeEnough(_ annotation: Annotation) -> Bool {
        switch annotation {
        case .arrow(let arrow):
            Geometry.distance(arrow.start, arrow.end) >= Self.minArrowDrag / fitScale
        case .blur(let blur):
            blur.rect.width >= EditorState.minBlurSize.width && blur.rect.height >= EditorState.minBlurSize.height
        case .text:
            false
        }
    }

    /// Top-down hit-test: text and arrows before blurs, newest first (spec §5.8).
    private func hitTest(imagePoint point: CGPoint) -> Annotation? {
        let tolerance = Self.hitTolerance / fitScale
        let topDown = state.document.annotations.reversed()
        return topDown.first { !$0.isBlur && $0.contains(point, tolerance: tolerance) }
            ?? topDown.first { $0.isBlur && $0.contains(point, tolerance: tolerance) }
    }
}
