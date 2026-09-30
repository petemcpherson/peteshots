//
//  EditorWindowController.swift
//  peteshots
//

import AppKit
import OSLog
import SwiftUI

/// The editor window for one capture (spec §5.1). Closing it by any route
/// discards the capture with no prompt.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    static let toolbarHeight: CGFloat = 44
    static let minimumContentSize = CGSize(width: 480, height: 240)

    let state: EditorState
    private let editorUndoManager = UndoManager()
    private let onClose: () -> Void
    private let captureScreen: NSScreen
    private let logger = Logger(subsystem: "com.peteshots.peteshots", category: "export")

    init(image: CGImage, captureRect: CGRect, captureDate: Date, screen: NSScreen, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.captureScreen = screen

        // Image size in points: a Retina capture shows at its on-screen size (spec §11).
        let pointsPerPixel = captureRect.width / CGFloat(image.width)
        let state = EditorState(baseImage: image, pointsPerPixel: pointsPerPixel)
        self.state = state

        let window = EditorWindow(
            contentRect: CGRect(origin: .zero, size: Self.minimumContentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Peteshots"
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumContentSize
        window.contentView = NSHostingView(rootView: EditorView(state: state))
        window.setContentSize(Self.contentSize(image: image, pointsPerPixel: pointsPerPixel, window: window, screen: screen))

        let visible = screen.visibleFrame
        window.setFrameOrigin(CGPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        ))

        super.init(window: window)
        window.delegate = self
        window.keyHandler = { [weak state] event in state?.handleKey(event) ?? false }

        state.undoManager = editorUndoManager
        state.captureDate = captureDate
        state.onSaved = { [weak self] result in
            guard let self else { return }
            ToastPresenter.shared.show(.saved(result), on: captureScreen)
            close()
        }
        state.onSaveFailed = { [weak self] error in
            // The editor stays open.
            guard let self else { return }
            ToastPresenter.shared.show(.error("Save failed", error), on: captureScreen)
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
        state.onCancel = { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The image at 1:1 in points plus the toolbar, scaled down to fit 85% of
    /// the screen's visible frame, and no smaller than the minimum size.
    private static func contentSize(image: CGImage, pointsPerPixel: CGFloat, window: NSWindow, screen: NSScreen) -> CGSize {
        let imageSize = CGSize(width: CGFloat(image.width) * pointsPerPixel, height: CGFloat(image.height) * pointsPerPixel)
        let maxFrame = CGSize(width: screen.visibleFrame.width * 0.85, height: screen.visibleFrame.height * 0.85)
        let maxContent = window.contentRect(forFrameRect: CGRect(origin: .zero, size: maxFrame)).size
        let maxImage = CGSize(width: maxContent.width, height: maxContent.height - toolbarHeight)
        let fit = min(1, maxImage.width / imageSize.width, maxImage.height / imageSize.height)
        return CGSize(
            width: max(minimumContentSize.width, (imageSize.width * fit).rounded()),
            height: max(minimumContentSize.height, (imageSize.height * fit).rounded() + toolbarHeight)
        )
    }

    func present() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        editorUndoManager.removeAllActions()
        // onClose releases the coordinator's reference to this controller.
        withExtendedLifetime(self) { onClose() }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editorUndoManager
    }
}

/// Routes editor keys: Cmd-S, Cmd-Z, and Cmd-Shift-Z as key equivalents, and
/// plain keys (tools, Delete, Esc) that no view consumed.
final class EditorWindow: NSWindow {
    var keyHandler: (NSEvent) -> Bool = { _ in false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        let textIsEditing = firstResponder is NSTextView

        switch (modifiers, key) {
        case ([.command], "s"):
            if let controller = windowController as? EditorWindowController {
                controller.state.save()
            }
            return true
        // The first responder's undo manager: the inline text editor has its own.
        case ([.command], "z"):
            (firstResponder ?? self).undoManager?.undo()
            return true
        case ([.command, .shift], "z"):
            (firstResponder ?? self).undoManager?.redo()
            return true
        // The app has no visible Edit menu, so the inline text editor gets
        // these directly.
        case ([.command], "x") where textIsEditing:
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case ([.command], "c") where textIsEditing:
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case ([.command], "v") where textIsEditing:
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case ([.command], "a") where textIsEditing:
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case ([.command], "w"):
            performClose(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if !keyHandler(event) {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if let controller = windowController as? EditorWindowController {
            controller.state.escape()
        }
    }
}
