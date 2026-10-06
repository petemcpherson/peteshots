//
//  ImageEncoder.swift
//  peteshots
//

import ImageIO
import UniformTypeIdentifiers

/// Encodes images with ImageIO (spec §7.3).
nonisolated enum ImageEncoder {
    enum EncodeError: Error {
        case failed
    }

    /// JPEG quality when compression is off.
    static let uncompressedJPEGQuality = 0.95

    /// Encodes `image`. Compression on uses `jpegQuality` for JPEG and the
    /// `pngCompression` palette for PNG, and removes the EXIF block (spec §7.3).
    static func encode(
        _ image: CGImage,
        format: ImageFormat,
        compressed: Bool,
        jpegQuality: Double,
        pngCompression: PNGCompression = AppSettings.Default.pngCompression
    ) throws -> Data {
        let type: UTType = format == .png ? .png : .jpeg
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw EncodeError.failed
        }

        var properties: [CFString: Any] = [:]
        var encoded = image
        switch format {
        case .jpeg:
            properties[kCGImageDestinationLossyCompressionQuality] = compressed ? jpegQuality : uncompressedJPEGQuality
        case .png:
            // ImageIO has no PNG compression level, so reduce the colors instead.
            if compressed, let quantized = PNGQuantizer.quantize(image, maxColors: pngCompression.maxColors, dither: pngCompression.dither) {
                encoded = quantized
            }
        }

        CGImageDestinationAddImage(destination, encoded, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EncodeError.failed }
        guard compressed else { return data as Data }
        switch format {
        case .png: return stripPNGExif(data as Data)
        case .jpeg: return stripJPEGExif(data as Data)
        }
    }

    // MARK: - Metadata

    // ImageIO always writes a small EXIF block (color space and pixel size),
    // and no destination option turns it off. These remove it from the file.

    /// The PNG without its `eXIf` chunk. Other chunks are copied unchanged.
    static func stripPNGExif(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        let signatureLength = 8
        guard bytes.count > signatureLength else { return data }
        var output = Data(bytes[0..<signatureLength])
        var offset = signatureLength
        // Each chunk: 4-byte length, 4-byte type, data, 4-byte CRC.
        while offset + 12 <= bytes.count {
            let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let end = offset + 12 + length
            guard end <= bytes.count else { return data }
            if bytes[offset + 4..<offset + 8].elementsEqual("eXIf".utf8) == false {
                output.append(contentsOf: bytes[offset..<end])
            }
            offset = end
        }
        return offset == bytes.count ? output : data
    }

    /// The JPEG without its EXIF `APP1` segment. Other segments and the
    /// image data are copied unchanged.
    static func stripJPEGExif(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return data }
        var output = Data(bytes[0..<2])
        var offset = 2
        // Header segments: 0xFF, marker, 2-byte length (including itself), payload.
        // Start of scan (0xDA) begins the image data, which is copied as is.
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF, bytes[offset + 1] != 0xDA {
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let end = offset + 2 + length
            guard length >= 2, end <= bytes.count else { return data }
            let isExif = bytes[offset + 1] == 0xE1 && bytes[offset + 4..<end].starts(with: "Exif\0\0".utf8)
            if !isExif {
                output.append(contentsOf: bytes[offset..<end])
            }
            offset = end
        }
        guard offset + 2 <= bytes.count, bytes[offset + 1] == 0xDA else { return data }
        output.append(contentsOf: bytes[offset...])
        return output
    }
}
