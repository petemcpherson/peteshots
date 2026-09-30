//
//  CaptureCoordinator.swift
//  peteshots
//

import AppKit
import OSLog

/// Drives one capture from hotkey to editor (spec §4).
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    enum State {
        case idle
        case selecting
        case capturing
        case editing(EditorWindowController)
    }

    private(set) var state: State = .idle

    /// Set at mouse-up. The editor and the file name use these.
    private(set) var captureDate: Date?
    private(set) var captureScreen: NSScreen?
    private(set) var captureRect: CGRect?

    private var overlay: SelectionOverlay?
    private let logger = Logger(subsystem: "com.peteshots.peteshots", category: "capture")

    func start() {
        switch state {
        case .selecting, .capturing:
            return
        case .editing(let controller):
            NSApp.activate()
            controller.window?.makeKeyAndOrderFront(nil)
        case .idle:
            guard PermissionService.ensureScreenCaptureAccess() else { return }
            showOverlay()
        }
    }

    private func showOverlay() {
        state = .selecting
        let overlay = SelectionOverlay(
            onComplete: { [weak self] rect in self?.didSelect(rect) },
            onCancel: { [weak self] in self?.reset() }
        )
        self.overlay = overlay
        overlay.show()
    }

    private func didSelect(_ rect: CGRect) {
        state = .capturing
        captureDate = Date()
        captureRect = rect
        captureScreen = Self.screen(for: rect)

        overlay?.close()
        overlay = nil

        Task {
            do {
                // Give the window server a moment to remove the overlay from the screen.
                try await Task.sleep(for: .milliseconds(40))
                let image = try await ScreenCapturer.capture(cocoaRect: rect)
                showEditor(image)
            } catch {
                logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                ToastPresenter.shared.show(.error("Capture failed", error), on: captureScreen)
                reset()
            }
        }
    }

    private func showEditor(_ image: CGImage) {
        guard let captureRect, let captureScreen, let captureDate else {
            reset()
            return
        }
        let controller = EditorWindowController(image: image, captureRect: captureRect, captureDate: captureDate, screen: captureScreen) { [weak self] in
            self?.reset()
        }
        state = .editing(controller)
        controller.present()
    }

    private func reset() {
        overlay?.close()
        overlay = nil
        captureDate = nil
        captureRect = nil
        captureScreen = nil
        state = .idle
    }

    /// The screen that holds the largest part of the rect.
    private static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            let areaA = a.frame.intersection(rect).size
            let areaB = b.frame.intersection(rect).size
            return areaA.width * areaA.height < areaB.width * areaB.height
        } ?? NSScreen.main
    }
}
