//
//  SelectionView.swift
//  peteshots
//

import AppKit

/// Draws the dim, the selection, and the size label for one screen.
final class SelectionView: NSView {
    private unowned let overlay: SelectionOverlay

    init(frame: CGRect, overlay: SelectionOverlay) {
        self.overlay = overlay
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    // MARK: - Coordinates

    /// This view's screen frame, in global Cocoa coordinates.
    private var screenFrame: CGRect {
        window?.frame ?? .zero
    }

    private func globalPoint(for event: NSEvent) -> CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func toLocal(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    // MARK: - Mouse and keys

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        overlay.mouseDown(at: globalPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        overlay.mouseDragged(to: globalPoint(for: event), square: event.modifierFlags.contains(.shift))
    }

    override func mouseMoved(with event: NSEvent) {
        overlay.mouseMoved(to: globalPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        overlay.mouseUp(at: globalPoint(for: event), square: event.modifierFlags.contains(.shift))
    }

    override func rightMouseDown(with event: NSEvent) {
        overlay.cancel()
    }

    override func flagsChanged(with event: NSEvent) {
        overlay.modifiersChanged(square: event.modifierFlags.contains(.shift))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            overlay.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        overlay.cancel()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.2).setFill()
        bounds.fill()

        guard let selection = overlay.selectionRect else { return }
        let local = toLocal(selection)
        guard local.intersects(bounds) else { return }

        NSColor.clear.setFill()
        local.fill(using: .copy)

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        drawSizeLabel(for: selection)
    }

    private func drawSizeLabel(for selection: CGRect) {
        guard let cursor = overlay.cursorLocation, screenFrame.contains(cursor) else { return }

        let scale = window?.backingScaleFactor ?? 1
        let width = Int((selection.width * scale).rounded())
        let height = Int((selection.height * scale).rounded())
        let text = NSAttributedString(string: "\(width) × \(height)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])

        let padding = CGSize(width: 6, height: 3)
        let textSize = text.size()
        let boxSize = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)

        // Below and to the right of the cursor, kept inside this screen.
        let localCursor = CGPoint(x: cursor.x - screenFrame.minX, y: cursor.y - screenFrame.minY)
        var origin = CGPoint(x: localCursor.x + 14, y: localCursor.y - 14 - boxSize.height)
        if origin.x + boxSize.width > bounds.maxX { origin.x = localCursor.x - 14 - boxSize.width }
        if origin.y < bounds.minY { origin.y = localCursor.y + 14 }

        let box = CGRect(origin: origin, size: boxSize)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height))
    }
}
