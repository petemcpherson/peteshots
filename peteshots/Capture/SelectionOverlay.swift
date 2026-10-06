//
//  SelectionOverlay.swift
//  peteshots
//

import AppKit

/// Borderless panel that can become key, so it receives Esc.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows one dimmed panel per screen and tracks a single drag in global
/// Cocoa coordinates, so one selection can cross displays (spec §4.3).
final class SelectionOverlay {
    /// Selections smaller than this (in points) count as a click and cancel.
    private static let minimumSize: CGFloat = 4

    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    private var panels: [OverlayPanel] = []
    private var views: [SelectionView] = []
    private var isCursorPushed = false

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isSquare = false

    /// Cursor position in global Cocoa coordinates, for the size label.
    private(set) var cursorLocation: CGPoint?

    init(onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    /// The current selection in global Cocoa coordinates.
    var selectionRect: CGRect? {
        guard let start = dragStart, var end = dragCurrent else { return nil }
        if isSquare {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let side = min(abs(dx), abs(dy))
            end = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    func show() {
        for screen in NSScreen.screens {
            let panel = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.ignoresMouseEvents = false
            panel.isReleasedWhenClosed = false
            panel.setFrame(screen.frame, display: false)

            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), overlay: self)
            panel.contentView = view
            panel.initialFirstResponder = view

            panels.append(panel)
            views.append(view)
        }

        for panel in panels {
            panel.orderFrontRegardless()
        }

        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { $0.frame.contains(mouse) } ?? panels.first
        keyPanel?.makeKeyAndOrderFront(nil)
        if let keyPanel, let view = keyPanel.contentView {
            keyPanel.makeFirstResponder(view)
        }

        NSCursor.crosshair.push()
        isCursorPushed = true
    }

    /// Removes the panels from the screen. Safe to call more than once.
    func close() {
        for panel in panels {
            // Stop event delivery before the panel leaves the screen.
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        }
        panels.removeAll()
        views.removeAll()
        if isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
    }

    // MARK: - Events from SelectionView

    func mouseDown(at point: CGPoint) {
        dragStart = point
        dragCurrent = point
        cursorLocation = point
        redraw()
    }

    func mouseDragged(to point: CGPoint, square: Bool) {
        guard dragStart != nil else { return }
        dragCurrent = point
        cursorLocation = point
        isSquare = square
        redraw()
    }

    func mouseMoved(to point: CGPoint) {
        cursorLocation = point
    }

    func modifiersChanged(square: Bool) {
        guard dragStart != nil, square != isSquare else { return }
        isSquare = square
        redraw()
    }

    func mouseUp(at point: CGPoint, square: Bool) {
        guard dragStart != nil else { return }
        dragCurrent = point
        isSquare = square
        guard let rect = selectionRect,
              rect.width >= Self.minimumSize, rect.height >= Self.minimumSize
        else {
            cancel()
            return
        }
        onComplete(rect)
    }

    func cancel() {
        close()
        onCancel()
    }

    private func redraw() {
        for view in views {
            view.needsDisplay = true
        }
    }
}
