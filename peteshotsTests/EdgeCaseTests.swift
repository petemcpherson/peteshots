import CoreGraphics
import Foundation
import Testing
@testable import peteshots

/// Edge cases from spec §11 that can run without a display.
struct EdgeCaseTests {
    private func settings(destination: URL) -> ExportSettings {
        ExportSettings(
            destinationURL: destination, filenamePrefix: "Edge", format: .png, resizeEnabled: true,
            maxLongSide: 2000, compressionEnabled: true, jpegQuality: 0.8, copyToClipboard: false
        )
    }

    @Test func writeToReadOnlyFolderThrows() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }

        let base = ExportTestImages.solid(width: 40, height: 30)
        #expect(throws: ExportPipeline.ExportError.self) {
            try ExportPipeline.export(
                base: base, document: EditorDocument(imageSize: CGSize(width: 40, height: 30)),
                captureDate: Date(), settings: settings(destination: folder)
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    /// A 6K capture: a blur region renders at the right size, fast enough to
    /// redraw during a drag.
    @Test func blurOnLargeImage() throws {
        let base = ExportTestImages.solid(width: 6016, height: 3384)
        let renderer = BlurRenderer.shared
        let clock = ContinuousClock()
        var slowest = Duration.zero
        for step in 0..<10 {
            // A new rect each step, as during a drag, so the cache never hits.
            let rect = CGRect(x: 1000 + step * 7, y: 800, width: 1200, height: 700)
            var image: CGImage?
            let elapsed = clock.measure { image = renderer.blurredImage(of: base, in: rect) }
            slowest = max(slowest, elapsed)
            #expect(image?.width == 1200)
            #expect(image?.height == 700)
        }
        #expect(slowest < .milliseconds(250))
    }

    @Test func largeImageExportResizes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let size = CGSize(width: 6016, height: 3384)
        let base = ExportTestImages.solid(width: Int(size.width), height: Int(size.height))
        var document = EditorDocument(imageSize: size)
        document.annotations = [.blur(BlurAnnotation(rect: CGRect(x: 100, y: 100, width: 800, height: 400)))]
        let result = try ExportPipeline.export(base: base, document: document, captureDate: Date(), settings: settings(destination: folder))
        #expect(result.didResize)
        #expect(result.finalSize == CGSize(width: 2000, height: 1125))
    }
}
