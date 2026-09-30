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

    /// Every PNG row filter. `IMAGEIO_PNG_ALL_FILTERS` is a compound macro
    /// that Swift does not import.
    private static let allPNGFilters = IMAGEIO_PNG_FILTER_NONE | IMAGEIO_PNG_FILTER_SUB | IMAGEIO_PNG_FILTER_UP
        | IMAGEIO_PNG_FILTER_AVG | IMAGEIO_PNG_FILTER_PAETH

    /// JPEG quality when compression is off.
    static let uncompressedJPEGQuality = 0.95

    /// Encodes `image`. Compression on uses `jpegQuality` for JPEG and
    /// adaptive filtering for PNG, and removes the EXIF block (spec §7.3).
    static func encode(_ image: CGImage, format: ImageFormat, compressed: Bool, jpegQuality: Double) throws -> Data {
        let type: UTType = format == .png ? .png : .jpeg
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw EncodeError.failed
        }

        var properties: [CFString: Any] = [:]
        switch format {
        case .jpeg:
            properties[kCGImageDestinationLossyCompressionQuality] = compressed ? jpegQuality : uncompressedJPEGQuality
        case .png:
            if compressed {
                // Try every PNG row filter and keep the smallest. Lossless.
                properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGCompressionFilter: allPNGFilters]
            }
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
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
