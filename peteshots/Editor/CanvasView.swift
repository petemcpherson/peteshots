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
        /// Scales a text box by a corner handle, from the text at drag start.
        case textResize(original: TextAnnotation, corner: Geometry.RectHandle)
        /// Creates a new annotation with the arrow or blur tool.
        case create(tool: Tool, start: CGPoint)
        /// Resizes the crop draft by one of its 8 handles.
        case cropResize(handle: Geometry.RectHandle)
        /// Moves the crop draft. Offsets are from the drag start, so rounding
        /// to whole pixels never loses slow movement.
        case cropMove(startRect: CGRect, startPoint: CGPoint)
    }

    private let state: EditorState
    private var drag: Drag?
    /// The annotation being created, drawn on top until mouse-up.
    private var draft: Annotation? {
        didSet { needsDisplay = true }
    }
    private var textOverlay: TextEditingOverlay?

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
        syncTextOverlay()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncTextOverlay()
    }

    private func observeState() {
        withObservationTracking {
            _ = state.document
            _ = state.selectedID
            _ = state.tool
            _ = state.editingTextID
            _ = state.cropDraft
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
                self.syncTextOverlay()
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

    /// The area shown, in image px: the full image in crop mode, otherwise the
    /// crop rect plus any background padding (spec §5.6b).
    var visibleImageRect: CGRect {
        if state.tool == .crop { return state.imageBounds }
        let crop = state.document.cropRect
        return state.document.background?.canvasRect(for: crop) ?? crop
    }

    /// View points per image pixel. Never larger than 1:1 on the capture screen.
    var fitScale: CGFloat {
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

    func imageToView(_ rect: CGRect) -> CGRect {
        let rect = rect.standardized
        return Geometry.rect(from: imageToView(rect.origin), to: imageToView(CGPoint(x: rect.maxX, y: rect.maxY)))
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
        if state.tool != .crop, let background = state.document.background {
            BackgroundDrawing.draw(background, crop: state.document.cropRect, in: context) {
                drawContent(in: context)
            }
        } else {
            drawContent(in: context)
        }
        context.restoreGState()

        if case .blur(let blur)? = draft {
            strokeOutline(of: blur.rect)
        }

        if state.tool == .crop, let crop = state.cropDraft {
            drawCropDraft(crop)
        } else {
            drawSelectionHandles()
        }
    }

    /// Dims the image outside the crop draft and shows its 8 handles (spec §5.7).
    private func drawCropDraft(_ crop: CGRect) {
        let dim = NSBezierPath(rect: imageToView(state.imageBounds))
        dim.append(NSBezierPath(rect: imageToView(crop)))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        dim.fill()

        strokeOutline(of: crop)
        drawHandles(at: Geometry.RectHandle.allCases.map { $0.point(in: crop) })
    }

    /// The base image, annotations, and draft, in image pixels.
    private func drawContent(in context: CGContext) {
        drawBaseImage(in: context)
        // The inline editor draws the text being edited.
        let annotations = state.document.annotations.filter { $0.id != state.editingTextID }
        AnnotationDrawing.draw(annotations, base: state.baseImage, in: context)
        if let id = state.editingTextID, case .text(let text)? = state.document.annotation(withID: id) {
            // The editor shows the fill; its outline draws here, under it.
            AnnotationDrawing.drawText(text, outlineOnly: true, in: context)
        }
        if let draft {
            AnnotationDrawing.draw([draft], base: state.baseImage, in: context)
        }
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
        guard let annotation = state.selectedAnnotation, annotation.id != state.editingTextID else { return }
        switch annotation {
        case .blur(let blur): strokeOutline(of: blur.rect)
        case .text(let text): strokeOutline(of: TextLayout.frame(of: text))
        case .arrow: break
        }
        drawHandles(at: annotation.handlePoints)
    }

    private func drawHandles(at points: [CGPoint]) {
        let size = Self.handleSize
        for point in points {
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

    /// A thin outline around a region (image px), drawn in view space.
    private func strokeOutline(of rect: CGRect) {
        let path = NSBezierPath(rect: imageToView(rect).insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        // A click outside the inline editor ends the edit (spec §5.6).
        state.endTextEditing()
        window?.makeFirstResponder(self)
        let point = viewToImage(convert(event.locationInWindow, from: nil))

        // Double-click a text box with any tool to edit it.
        if event.clickCount == 2, state.tool != .crop, case .text(let text)? = hitTest(imagePoint: point) {
            beginTextEditing(text, isNew: false)
            return
        }

        switch state.tool {
        case .select:
            beginSelectDrag(at: point)
        case .arrow, .blur:
            drag = .create(tool: state.tool, start: Geometry.clampPoint(point, to: state.imageBounds))
        case .text:
            if case .text(let text)? = hitTest(imagePoint: point) {
                beginTextEditing(text, isNew: false)
            } else {
                beginTextEditing(newTextAt: point)
            }
        case .crop:
            beginCropDrag(at: point)
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

        case .textResize(let original, let corner):
            state.updateLive { document in
                document.updateAnnotation(withID: original.id) { annotation in
                    annotation = .text(TextLayout.resize(original, corner: corner, to: point))
                }
            }

        case .create(let tool, let start):
            draft = makeDraft(tool: tool, from: start, to: Geometry.clampPoint(point, to: state.imageBounds))

        case .cropResize(let handle):
            guard let crop = state.cropDraft else { return }
            let clamped = Geometry.clampPoint(point, to: state.imageBounds)
            state.updateCropDraft(Geometry.resize(crop, handle: handle, to: clamped, minSize: EditorState.minCropSize))

        case .cropMove(let startRect, let startPoint):
            state.updateCropDraft(startRect.offsetBy(dx: point.x - startPoint.x, dy: point.y - startPoint.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil

        switch drag {
        case .move, .arrowEnd, .blurResize, .textResize:
            state.endLiveChange()
        case .create:
            if let draft, isLargeEnough(draft) {
                state.place(draft)
            }
            draft = nil
        case .cropResize, .cropMove:
            // The crop is committed when it is applied.
            break
        }
    }

    private func beginCropDrag(at point: CGPoint) {
        guard let crop = state.cropDraft else { return }
        if let handle = Geometry.handle(at: point, in: crop, radius: Self.handleSize / fitScale) {
            drag = .cropResize(handle: handle)
        } else if crop.contains(point) {
            drag = .cropMove(startRect: crop, startPoint: point)
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
        case .text(let text):
            return Geometry.handle(at: point, in: TextLayout.frame(of: text), radius: radius, cornersOnly: true)
                .map { .textResize(original: text, corner: $0) }
        }
    }

    private func makeDraft(tool: Tool, from start: CGPoint, to end: CGPoint) -> Annotation? {
        switch tool {
        case .arrow:
            .arrow(ArrowAnnotation(
                start: start, end: end, colorHex: state.colorHex,
                strokeWidth: state.arrowStrokeWidth, outline: state.outline
            ))
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

    // MARK: - Text editing

    /// Creates an empty text box with its first line centered on the click.
    private func beginTextEditing(newTextAt point: CGPoint) {
        let fontSize = state.defaultFontSize
        let lineHeight = fontSize * TextLayout.lineHeightMultiple
        // Not the background padding: text there would be clipped.
        let origin = Geometry.clampPoint(CGPoint(x: point.x, y: point.y - lineHeight / 2), to: state.document.cropRect)
        let text = TextAnnotation(origin: origin, string: "", fontSize: fontSize, colorHex: state.colorHex, outline: state.outline)
        beginTextEditing(text, isNew: true)
    }

    private func beginTextEditing(_ text: TextAnnotation, isNew: Bool) {
        state.beginTextEditing(text, isNew: isNew)
        syncTextOverlay()
    }

    /// Shows, moves, or removes the inline editor to match the state.
    private func syncTextOverlay() {
        guard let id = state.editingTextID, case .text(let text)? = state.document.annotation(withID: id) else {
            if let overlay = textOverlay {
                textOverlay = nil
                if window?.firstResponder === overlay {
                    window?.makeFirstResponder(self)
                }
                overlay.removeFromSuperview()
            }
            return
        }

        let overlay = textOverlay ?? makeTextOverlay(for: text)
        let scale = fitScale
        let backingScale = window?.backingScaleFactor ?? 2
        overlay.apply(
            fontSize: text.fontSize * scale,
            colorHex: text.colorHex,
            shadowBlur: TextLayout.shadowBlurRadius * scale * backingScale
        )
        overlay.setFrameOrigin(imageToView(text.origin))
    }

    private func makeTextOverlay(for text: TextAnnotation) -> TextEditingOverlay {
        let overlay = TextEditingOverlay(string: text.string)
        overlay.onChange = { [weak self] string in self?.state.updateEditingText(string) }
        overlay.onFinish = { [weak self] in self?.state.endTextEditing() }
        addSubview(overlay)
        textOverlay = overlay
        window?.makeFirstResponder(overlay)
        overlay.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        return overlay
    }
}
