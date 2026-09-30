import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import peteshots

struct FileNamerTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        components.timeZone = .current
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func formatsCaptureTime() {
        #expect(FileNamer.baseName(prefix: "Screenshot", date: date(2026, 9, 30, 14, 5)) == "Screenshot - 09-30-26 14.05")
        #expect(FileNamer.baseName(prefix: "Bug", date: date(2027, 1, 2, 3, 4)) == "Bug - 01-02-27 03.04")
    }

    @Test func cleansPrefix() {
        #expect(FileNamer.cleanPrefix("  a/b:c  ") == "abc")
        #expect(FileNamer.cleanPrefix("") == "Screenshot")
        #expect(FileNamer.cleanPrefix(" /: ") == "Screenshot")
        #expect(FileNamer.baseName(prefix: "", date: date(2026, 9, 30, 14, 5)) == "Screenshot - 09-30-26 14.05")
    }

    @Test func addsCollisionSuffixes() throws {
        let folder = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = FileNamer.availableURL(in: folder, baseName: "Shot", fileExtension: "png")
        #expect(first.lastPathComponent == "Shot.png")
        try Data().write(to: first)

        let second = FileNamer.availableURL(in: folder, baseName: "Shot", fileExtension: "png")
        #expect(second.lastPathComponent == "Shot (2).png")
        try Data().write(to: second)

        #expect(FileNamer.availableURL(in: folder, baseName: "Shot", fileExtension: "png").lastPathComponent == "Shot (3).png")
        #expect(FileNamer.availableURL(in: folder, baseName: "Shot", fileExtension: "jpg").lastPathComponent == "Shot.jpg")
    }

    @Test func fallsBackToDownloads() throws {
        let folder = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(FileNamer.resolveDestination(folder) == (folder, false))

        let missing = folder.appendingPathComponent("missing", isDirectory: true)
        let resolved = FileNamer.resolveDestination(missing)
        #expect(resolved.usedFallback)
        #expect(resolved.url == FileNamer.downloadsURL())

        let file = folder.appendingPathComponent("file.txt")
        try Data().write(to: file)
        #expect(FileNamer.resolveDestination(file).usedFallback)
    }
}

struct ImageResizerTests {
    @Test func noResizeAtOrBelowLimit() {
        #expect(ImageResizer.targetSize(width: 2000, height: 1000, maxLongSide: 2000) == nil)
        #expect(ImageResizer.targetSize(width: 100, height: 50, maxLongSide: 2000) == nil)
    }

    @Test func scalesLongSideToLimit() {
        let landscape = ImageResizer.targetSize(width: 4000, height: 2001, maxLongSide: 2000)
        #expect(landscape?.width == 2000 && landscape?.height == 1001)
        let portrait = ImageResizer.targetSize(width: 1000, height: 3000, maxLongSide: 2000)
        #expect(portrait?.width == 667 && portrait?.height == 2000)
    }

    @Test func resizesToExactDimensions() {
        let image = ExportTestImages.solid(width: 301, height: 157)
        let resized = ImageResizer.resize(image, width: 200, height: 104)
        #expect(resized?.width == 200)
        #expect(resized?.height == 104)
        #expect(resized?.alphaInfo == .noneSkipLast)
    }
}

struct ImageEncoderTests {
    @Test func pngHasNoAlphaOrExif() throws {
        let image = ExportTestImages.solid(width: 40, height: 30)
        let data = try ImageEncoder.encode(image, format: .png, compressed: true, jpegQuality: 0.8)
        let properties = try #require(ExportTestImages.properties(of: data))
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool != true)
        #expect(image.alphaInfo == .noneSkipLast)
        #expect(properties[kCGImagePropertyExifDictionary] == nil)
        #expect(!ExportTestImages.containsExif(data))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 40)
    }

    @Test func jpegHasNoExif() throws {
        let image = ExportTestImages.noise(width: 64, height: 64)
        let data = try ImageEncoder.encode(image, format: .jpeg, compressed: true, jpegQuality: 0.8)
        let properties = try #require(ExportTestImages.properties(of: data))
        #expect(properties[kCGImagePropertyExifDictionary] == nil)
        #expect(!ExportTestImages.containsExif(data))
        // Still a valid image after the strip.
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 64)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func jpegQualityChangesSize() throws {
        let image = ExportTestImages.noise(width: 128, height: 128)
        let low = try ImageEncoder.encode(image, format: .jpeg, compressed: true, jpegQuality: 0.6)
        let high = try ImageEncoder.encode(image, format: .jpeg, compressed: false, jpegQuality: 0.6)
        #expect(low.count < high.count)
    }
}

struct RendererTests {
    @Test func cropSetsOutputSize() {
        let base = ExportTestImages.solid(width: 200, height: 100)
        var document = EditorDocument(imageSize: CGSize(width: 200, height: 100))
        document.cropRect = CGRect(x: 20, y: 10, width: 120, height: 50)
        let output = Renderer.flatten(base: base, document: document)
        #expect(output?.width == 120)
        #expect(output?.height == 50)
        #expect(output?.alphaInfo == .noneSkipLast)
    }

    @Test func arrowDrawsInCroppedSpace() throws {
        let base = ExportTestImages.solid(width: 200, height: 100)
        var document = EditorDocument(imageSize: CGSize(width: 200, height: 100))
        document.cropRect = CGRect(x: 100, y: 0, width: 100, height: 100)
        // A horizontal red arrow at y = 20, from x = 110 to 190 in image space.
        let arrow = ArrowAnnotation(start: CGPoint(x: 110, y: 20), end: CGPoint(x: 190, y: 20), colorHex: "#FF0000", strokeWidth: 6)
        document.annotations = [.arrow(arrow)]
        let output = try #require(Renderer.flatten(base: base, document: document))

        let onLine = ExportTestImages.pixel(output, x: 40, y: 20)
        #expect(onLine.r > 240 && onLine.g < 20 && onLine.b < 20)
        let below = ExportTestImages.pixel(output, x: 40, y: 80)
        #expect(below.r > 240 && below.g > 240 && below.b > 240)
    }

    @Test func pipelineWritesFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let base = ExportTestImages.noise(width: 300, height: 120)
        let settings = ExportSettings(
            destinationURL: folder, filenamePrefix: "Test", format: .jpeg, resizeEnabled: true,
            maxLongSide: 150, compressionEnabled: true, jpegQuality: 0.8, copyToClipboard: false
        )
        let result = try ExportPipeline.export(
            base: base, document: EditorDocument(imageSize: CGSize(width: 300, height: 120)),
            captureDate: Date(), settings: settings
        )
        #expect(FileManager.default.fileExists(atPath: result.url.path))
        #expect(result.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(result.url.pathExtension == "jpg")
        #expect(result.fileName.hasPrefix("Test - "))
        #expect(result.didResize)
        #expect(result.originalSize == CGSize(width: 300, height: 120))
        #expect(result.finalSize == CGSize(width: 150, height: 60))
        #expect(result.showCompression)
        #expect(result.finalBytes < result.uncompressedBytes)
        #expect(!result.usedFallback)
    }
}

enum ExportTestImages {
    static func context(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
    }

    static func solid(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Random pixels, so JPEG quality has a visible effect on size.
    static func noise(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height)
        var generator = SystemRandomNumberGenerator()
        for y in 0..<height {
            for x in 0..<width {
                context.setFillColor(CGColor(
                    srgbRed: .random(in: 0...1, using: &generator),
                    green: .random(in: 0...1, using: &generator),
                    blue: .random(in: 0...1, using: &generator),
                    alpha: 1
                ))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    static func containsExif(_ data: Data) -> Bool {
        data.range(of: Data("Exif".utf8)) != nil || data.range(of: Data("eXIf".utf8)) != nil
    }

    static func properties(of data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// RGB at a top-left origin pixel, read by redrawing into a known layout.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let context = context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (data[offset], data[offset + 1], data[offset + 2])
    }
}
