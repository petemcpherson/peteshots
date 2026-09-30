//
//  ScreenCapturer.swift
//  peteshots
//

import ScreenCaptureKit

enum ScreenCapturer {
    /// Captures a region given in Cocoa global coordinates. The result stays in memory.
    static func capture(cocoaRect: CGRect) async throws -> CGImage {
        let cgRect = CoordinateSpace.cgRect(fromCocoa: cocoaRect)
        return try await SCScreenshotManager.captureImage(in: cgRect)
    }
}
