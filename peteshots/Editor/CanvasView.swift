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

    private let state: EditorState

    /// The annotation being moved and the last drag point (image px).
    private var moveDrag: (id: Annotation.ID, last: CGPoint)?

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
                self?.needsDisplay = true
                self?.observeState()
            }
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
        // Annotations draw here through AnnotationDrawing (Phase 4).
        context.restoreGState()

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

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = viewToImage(convert(event.locationInWindow, from: nil))

        switch state.tool {
        case .select:
            selectAndBeginMove(at: point)
        case .arrow, .blur, .text, .crop:
            // Tool input arrives in Phases 4 and 5.
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let moveDrag else { return }
        let point = viewToImage(convert(event.locationInWindow, from: nil))
        let dx = point.x - moveDrag.last.x
        let dy = point.y - moveDrag.last.y
        state.updateLive { document in
            document.updateAnnotation(withID: moveDrag.id) { $0 = $0.offsetBy(dx: dx, dy: dy) }
        }
        self.moveDrag = (moveDrag.id, point)
    }

    override func mouseUp(with event: NSEvent) {
        guard moveDrag != nil else { return }
        moveDrag = nil
        state.endLiveChange()
    }

    private func selectAndBeginMove(at point: CGPoint) {
        guard let annotation = hitTest(imagePoint: point) else {
            state.selectedID = nil
            return
        }
        state.selectedID = annotation.id
        state.beginLiveChange()
        moveDrag = (annotation.id, point)
    }

    /// Top-down hit-test: text and arrows before blurs, newest first (spec §5.8).
    private func hitTest(imagePoint point: CGPoint) -> Annotation? {
        let tolerance = Self.hitTolerance / fitScale
        let topDown = state.document.annotations.reversed()
        return topDown.first { !$0.isBlur && $0.contains(point, tolerance: tolerance) }
            ?? topDown.first { $0.isBlur && $0.contains(point, tolerance: tolerance) }
    }
}
