//
//  ToastPanel.swift
//  peteshots
//

import AppKit
import SwiftUI

/// A small non-activating notification panel (spec §8). Only one toast shows
/// at a time: a new toast replaces the old one.
final class ToastPresenter {
    static let shared = ToastPresenter()

    private static let margin: CGFloat = 12
    private static let fadeIn: TimeInterval = 0.2
    private static let fadeOut: TimeInterval = 0.3

    private var panel: ToastPanel?
    /// Bumped for each toast, so an old timer does not hide a newer toast.
    private var generation = 0

    func show(_ content: ToastContent, on screen: NSScreen?) {
        panel?.orderOut(nil)
        generation += 1
        let current = generation

        let panel = ToastPanel(content: content) { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        self.panel = panel

        let visible = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: visible.maxX - size.width - Self.margin,
            y: visible.maxY - size.height - Self.margin
        ))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn
            panel.animator().alphaValue = 1
        }

        let visibleFor: Duration = content.style == .error ? .seconds(4) : .milliseconds(2500)
        Task {
            try? await Task.sleep(for: .seconds(Self.fadeIn) + visibleFor)
            guard current == generation else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeOut
                panel.animator().alphaValue = 0
            }
            guard current == generation else { return }
            // Out of the window list, so it steals no clicks.
            panel.orderOut(nil)
            self.panel = nil
        }
    }
}

final class ToastPanel: NSPanel {
    init(content: ToastContent, onClick: @escaping (URL) -> Void) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        let background = ToastBackgroundView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        if let url = content.fileURL {
            background.onClick = { onClick(url) }
        }

        let hosting = NSHostingView(rootView: ToastView(content: content))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        background.frame = hosting.frame
        background.addSubview(hosting)
        contentView = background
        setContentSize(size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes every click in the toast, so the hosted SwiftUI view does not need to.
private final class ToastBackgroundView: NSVisualEffectView {
    var onClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
