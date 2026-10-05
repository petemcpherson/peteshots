//
//  ExportPipeline.swift
//  peteshots
//

import CoreGraphics
import Foundation

/// What one save produced. The toast shows it (spec §8).
nonisolated struct ExportResult: Sendable {
    var url: URL
    var fileName: String
    var originalSize: CGSize
    var finalSize: CGSize
    var didResize: Bool
    var uncompressedBytes: Int
    var finalBytes: Int
    /// True when compression is on and saved at least 1%.
    var showCompression: Bool
    var usedFallback: Bool
    /// The written bytes, for the clipboard.
    var data: Data
    var format: ImageFormat

    nonisolated(unsafe) private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var formattedOriginalBytes: String { Self.byteFormatter.string(fromByteCount: Int64(uncompressedBytes)) }
    var formattedFinalBytes: String { Self.byteFormatter.string(fromByteCount: Int64(finalBytes)) }
}

/// Crop, flatten, resize, encode, and write (spec §7). Runs off the main thread.
nonisolated enum ExportPipeline {
    enum ExportError: LocalizedError {
        case renderFailed
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .renderFailed: "The image could not be rendered."
            case .writeFailed(let error): error.localizedDescription
            }
        }
    }

    static func export(
        base: CGImage,
        document: EditorDocument,
        captureDate: Date,
        settings: ExportSettings
    ) throws -> ExportResult {
        guard var image = Renderer.flatten(base: base, document: document) else {
            throw ExportError.renderFailed
        }
        let originalSize = CGSize(width: image.width, height: image.height)

        var didResize = false
        if settings.resizeEnabled,
           let target = ImageResizer.targetSize(width: image.width, height: image.height, maxLongSide: settings.maxLongSide) {
            guard let resized = ImageResizer.resize(image, width: target.width, height: target.height) else {
                throw ExportError.renderFailed
            }
            image = resized
            didResize = true
        }

        let uncompressed = try ImageEncoder.encode(image, format: settings.format, compressed: false, jpegQuality: settings.jpegQuality)
        var data = uncompressed
        var showCompression = false
        if settings.compressionEnabled {
            let compressed = try ImageEncoder.encode(image, format: settings.format, compressed: true, jpegQuality: settings.jpegQuality)
            // Keep the uncompressed data if compression made the file bigger (spec §7.3).
            if compressed.count < uncompressed.count {
                data = compressed
                // Under 1% rounds to the same size in the toast, so hide the line.
                showCompression = compressed.count * 100 <= uncompressed.count * 99
            }
        }

        let destination = FileNamer.resolveDestination(settings.destinationURL)
        let url = FileNamer.availableURL(
            in: destination.url,
            baseName: FileNamer.baseName(prefix: settings.filenamePrefix, date: captureDate),
            fileExtension: settings.format.fileExtension
        )
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error)
        }

        return ExportResult(
            url: url,
            fileName: url.lastPathComponent,
            originalSize: originalSize,
            finalSize: CGSize(width: image.width, height: image.height),
            didResize: didResize,
            uncompressedBytes: uncompressed.count,
            finalBytes: data.count,
            showCompression: showCompression,
            usedFallback: destination.usedFallback,
            data: data,
            format: settings.format
        )
    }
}
