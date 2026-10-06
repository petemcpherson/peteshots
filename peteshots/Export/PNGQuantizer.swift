//
//  PNGQuantizer.swift
//  peteshots
//

import CoreGraphics
import Foundation

/// Reduces an image to at most `maxColors` colors (up to 256) so ImageIO
/// writes an indexed (palette) PNG. Images that already fit convert
/// losslessly. Other images use median cut on the exact color histogram,
/// then optional Floyd–Steinberg dithering.
nonisolated enum PNGQuantizer {
    static let maxColors = 256

    private struct Color {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var key: UInt32 { UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
    }

    private struct Entry {
        var color: Color
        var count: Int
    }

    /// Returns an 8-bit indexed image, or nil if drawing fails.
    static func quantize(_ image: CGImage, maxColors: Int = Self.maxColors, dither: Bool = true) -> CGImage? {
        let limit = min(max(maxColors, 2), Self.maxColors)
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let rgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var counts: [UInt32: Int] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let key = UInt32(pixels[offset]) << 16 | UInt32(pixels[offset + 1]) << 8 | UInt32(pixels[offset + 2])
            counts[key, default: 0] += 1
        }
        let entries = counts.map { key, count in
            Entry(color: Color(r: UInt8(key >> 16 & 0xFF), g: UInt8(key >> 8 & 0xFF), b: UInt8(key & 0xFF)), count: count)
        }

        let isExact = entries.count <= limit
        let palette = isExact ? entries.map(\.color) : medianCut(entries, maxColors: limit)
        let indices = mapPixels(pixels, width: width, height: height, palette: palette, dither: dither && !isExact)

        var table: [UInt8] = []
        table.reserveCapacity(palette.count * 3)
        for color in palette {
            table += [color.r, color.g, color.b]
        }
        guard let indexed = CGColorSpace(indexedBaseSpace: rgb, last: palette.count - 1, colorTable: table),
              let provider = CGDataProvider(data: Data(indices) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: indexed, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// Splits the color histogram into `maxColors` boxes. Each box gives one
    /// palette color: its dominant color when one covers half the box (keeps
    /// flat UI colors exact), otherwise the weighted mean.
    private static func medianCut(_ entries: [Entry], maxColors: Int) -> [Color] {
        var colors = entries
        var boxes: [Range<Int>] = [0..<colors.count]

        func channel(_ color: Color, _ axis: Int) -> UInt8 {
            axis == 0 ? color.r : axis == 1 ? color.g : color.b
        }

        /// The widest axis of a box and its range.
        func widestAxis(_ box: Range<Int>) -> (axis: Int, range: Int) {
            var best = (axis: 0, range: 0)
            for axis in 0..<3 {
                var low = UInt8.max
                var high = UInt8.min
                for index in box {
                    let value = channel(colors[index].color, axis)
                    low = min(low, value)
                    high = max(high, value)
                }
                let range = Int(high) - Int(low)
                if range > best.range { best = (axis, range) }
            }
            return best
        }

        func score(_ box: Range<Int>) -> Int {
            guard box.count > 1 else { return 0 }
            let population = colors[box].reduce(0) { $0 + $1.count }
            return widestAxis(box).range * population
        }

        var scores = boxes.map(score)
        while boxes.count < maxColors, let best = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[best] > 0 {
            let box = boxes[best]
            let axis = widestAxis(box).axis
            colors[box].sort { channel($0.color, axis) < channel($1.color, axis) }

            let half = colors[box].reduce(0) { $0 + $1.count } / 2
            var running = 0
            var split = box.lowerBound + 1
            for index in box.dropLast() {
                running += colors[index].count
                split = index + 1
                if running >= half { break }
            }

            let lower = box.lowerBound..<split
            let upper = split..<box.upperBound
            boxes[best] = lower
            scores[best] = score(lower)
            boxes.append(upper)
            scores.append(score(upper))
        }

        return boxes.map { box in
            let slice = colors[box]
            let population = slice.reduce(0) { $0 + $1.count }
            if let dominant = slice.max(by: { $0.count < $1.count }), dominant.count * 2 >= population {
                return dominant.color
            }
            var sums = (r: 0, g: 0, b: 0)
            for entry in slice {
                sums.r += Int(entry.color.r) * entry.count
                sums.g += Int(entry.color.g) * entry.count
                sums.b += Int(entry.color.b) * entry.count
            }
            return Color(
                r: UInt8((sums.r + population / 2) / population),
                g: UInt8((sums.g + population / 2) / population),
                b: UInt8((sums.b + population / 2) / population)
            )
        }
    }

    /// Maps each pixel to a palette index. Exact palette colors map directly;
    /// other colors use the nearest palette color, cached per 6-bit cell.
    private static func mapPixels(_ pixels: [UInt8], width: Int, height: Int, palette: [Color], dither: Bool) -> [UInt8] {
        var exact: [UInt32: UInt8] = [:]
        for (index, color) in palette.enumerated() {
            exact[color.key] = UInt8(index)
        }
        var cache = [Int16](repeating: -1, count: 1 << 18)

        func nearest(_ r: Int, _ g: Int, _ b: Int) -> UInt8 {
            if let index = exact[UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)] { return index }
            let cell = (r >> 2) << 12 | (g >> 2) << 6 | (b >> 2)
            if cache[cell] >= 0 { return UInt8(cache[cell]) }
            var best = 0
            var bestDistance = Int.max
            for (index, color) in palette.enumerated() {
                let dr = r - Int(color.r), dg = g - Int(color.g), db = b - Int(color.b)
                let distance = dr * dr + dg * dg + db * db
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            cache[cell] = Int16(best)
            return UInt8(best)
        }

        var indices = [UInt8](repeating: 0, count: width * height)
        // Error rows in 1/16 units, padded by one pixel on each side.
        var current = [Int](repeating: 0, count: (width + 2) * 3)
        var next = current

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let e = (x + 1) * 3
                let r = min(255, max(0, Int(pixels[offset]) + current[e] / 16))
                let g = min(255, max(0, Int(pixels[offset + 1]) + current[e + 1] / 16))
                let b = min(255, max(0, Int(pixels[offset + 2]) + current[e + 2] / 16))
                let index = nearest(r, g, b)
                indices[y * width + x] = index
                guard dither else { continue }

                let chosen = palette[Int(index)]
                for (c, error) in [r - Int(chosen.r), g - Int(chosen.g), b - Int(chosen.b)].enumerated() where error != 0 {
                    current[e + 3 + c] += error * 7
                    next[e - 3 + c] += error * 3
                    next[e + c] += error * 5
                    next[e + 3 + c] += error
                }
            }
            swap(&current, &next)
            for i in next.indices { next[i] = 0 }
        }
        return indices
    }
}
