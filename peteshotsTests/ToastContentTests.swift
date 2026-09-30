//
//  ToastContentTests.swift
//  peteshotsTests
//

import Foundation
import Testing
@testable import peteshots

struct ToastContentTests {
    private func result(
        didResize: Bool = false,
        showCompression: Bool = false,
        usedFallback: Bool = false
    ) -> ExportResult {
        ExportResult(
            url: URL(fileURLWithPath: "/tmp/Screenshot - 09-30-26 14.05.png"),
            fileName: "Screenshot - 09-30-26 14.05.png",
            originalSize: CGSize(width: 2354, height: 1480),
            finalSize: didResize ? CGSize(width: 2000, height: 1257) : CGSize(width: 2354, height: 1480),
            didResize: didResize,
            uncompressedBytes: 1_800_000,
            finalBytes: showCompression ? 1_100_000 : 1_800_000,
            showCompression: showCompression,
            usedFallback: usedFallback,
            data: Data(),
            format: .png
        )
    }

    @Test func savedOnlyShowsSavedLine() {
        let content = ToastContent.saved(result())
        #expect(content.lines == ["✓ Saved \"Screenshot - 09-30-26 14.05.png\""])
        #expect(content.style == .success)
        #expect(content.fileURL?.lastPathComponent == "Screenshot - 09-30-26 14.05.png")
    }

    @Test func savedShowsResizeAndCompressionLines() {
        let content = ToastContent.saved(result(didResize: true, showCompression: true))
        #expect(content.lines.count == 3)
        #expect(content.lines[1] == "↘ Resized 2354×1480 → 2000×1257")
        #expect(content.lines[2].hasPrefix("🗜 "))
        #expect(content.lines[2].contains(" 👉 "))
    }

    @Test func savedShowsFallbackWarning() {
        let content = ToastContent.saved(result(usedFallback: true))
        #expect(content.lines.count == 2)
        #expect(content.lines[1].contains("Downloads"))
    }

    @Test func errorHasNoFileAndErrorStyle() {
        let content = ToastContent.error("Save failed", CocoaError(.fileWriteNoPermission))
        #expect(content.style == .error)
        #expect(content.fileURL == nil)
        #expect(content.lines.first == "✕ Save failed")
    }
}
