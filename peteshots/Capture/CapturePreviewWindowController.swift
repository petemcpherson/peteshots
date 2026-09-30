//
//  CapturePreviewWindowController.swift
//  peteshots
//

import AppKit

/// Temporary check (Phase 2 only): shows the captured image so the region
/// and resolution can be confirmed. Phase 3 replaces it with the editor.
final class CapturePreviewWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(image: CGImage, captureRect: CGRect, screen: NSScreen, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let scale = CGFloat(image.width) / captureRect.width
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let maxSize = CGSize(width: screen.visibleFrame.width * 0.85, height: screen.visibleFrame.height * 0.85)
        let fit = min(1, maxSize.width / size.width, maxSize.height / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Capture \(image.width) × \(image.height) px"
        window.isReleasedWhenClosed = false

        let imageView = NSImageView()
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = imageView

        let visible = screen.visibleFrame
        window.setFrameOrigin(CGPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        ))

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
