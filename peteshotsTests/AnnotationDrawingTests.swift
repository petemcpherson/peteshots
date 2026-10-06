import CoreGraphics
import Testing
@testable import peteshots

struct AnnotationDrawingTests {
    /// A white sRGB image, or a left-black/right-white split.
    private func makeImage(width: Int, height: Int, split: Bool = false) -> CGImage {
        let context = makeContext(width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if split {
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
        return context.makeImage()!
    }

    private func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
    }

    /// A context flipped to image pixel space with a top-left origin.
    private func makeFlippedContext(width: Int, height: Int) -> CGContext {
        let context = makeContext(width: width, height: height)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        return context
    }

    /// RGB at a top-left origin pixel.
    private func pixel(_ context: CGContext, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (data[offset], data[offset + 1], data[offset + 2])
    }

    @Test func arrowDrawsColorAlongLine() {
        let base = makeImage(width: 100, height: 60)
        let context = makeFlippedContext(width: 100, height: 60)
        context.draw(base, in: CGRect(x: 0, y: 0, width: 100, height: 60))
        let arrow = ArrowAnnotation(start: CGPoint(x: 10, y: 30), end: CGPoint(x: 90, y: 30), colorHex: "#FF0000", strokeWidth: 4)
        AnnotationDrawing.draw([.arrow(arrow)], base: base, in: context)

        let onLine = pixel(context, x: 40, y: 30)
        #expect(onLine.r > 240 && onLine.g < 20 && onLine.b < 20)
        let offLine = pixel(context, x: 40, y: 5)
        #expect(offLine.r > 240 && offLine.g > 240)
        // The head is wider than the line near the tip.
        let headEdge = pixel(context, x: 77, y: 34)
        #expect(headEdge.r > 200 && headEdge.g < 60)
    }

    @Test func arrowOutlineSurroundsLine() {
        let base = makeImage(width: 100, height: 60)
        let context = makeFlippedContext(width: 100, height: 60)
        context.draw(base, in: CGRect(x: 0, y: 0, width: 100, height: 60))
        let arrow = ArrowAnnotation(
            start: CGPoint(x: 10, y: 30), end: CGPoint(x: 90, y: 30), colorHex: "#FF0000", strokeWidth: 8,
            outline: Outline(colorHex: "#0000FF", width: .thick)
        )
        AnnotationDrawing.draw([.arrow(arrow)], base: base, in: context)

        // The line is 8 px wide with a 4 px outline on each side.
        let onLine = pixel(context, x: 40, y: 30)
        #expect(onLine.r > 240 && onLine.b < 20)
        let outline = pixel(context, x: 40, y: 36)
        #expect(outline.b > 240 && outline.r < 20)
        let outside = pixel(context, x: 40, y: 42)
        #expect(outside.r > 240 && outside.g > 240 && outside.b > 240)
    }

    @Test func textOutlineDrawsOutsideGlyphs() {
        let base = makeImage(width: 120, height: 80)
        let context = makeFlippedContext(width: 120, height: 80)
        context.draw(base, in: CGRect(x: 0, y: 0, width: 120, height: 80))
        let text = TextAnnotation(
            origin: CGPoint(x: 10, y: 10), string: "I", fontSize: 60, colorHex: "#FF0000",
            outline: Outline(colorHex: "#0000FF", width: .thick)
        )
        AnnotationDrawing.draw([.text(text)], base: base, in: context)

        var sawFill = false
        var sawOutline = false
        for y in 10..<80 {
            for x in 0..<120 {
                let p = pixel(context, x: x, y: y)
                if p.r > 240 && p.b < 20 { sawFill = true }
                if p.b > 240 && p.r < 20 { sawOutline = true }
            }
        }
        #expect(sawFill)
        #expect(sawOutline)
    }

    @Test func blurMixesPixelsInsideRegionOnly() {
        let base = makeImage(width: 200, height: 100, split: true)
        let context = makeFlippedContext(width: 200, height: 100)
        context.draw(base, in: CGRect(x: 0, y: 0, width: 200, height: 100))
        let blur = BlurAnnotation(rect: CGRect(x: 60, y: 10, width: 80, height: 80))
        AnnotationDrawing.draw([.blur(blur)], base: base, in: context)

        // At the black/white edge inside the blur, the pixel is gray.
        let edge = pixel(context, x: 100, y: 50)
        #expect(edge.r > 40 && edge.r < 215)
        // Outside the blur, the edge stays sharp.
        #expect(pixel(context, x: 98, y: 5).r < 5)
        #expect(pixel(context, x: 101, y: 5).r > 250)
    }

    @Test func blurRadiusIsClamped() {
        #expect(BlurRenderer.radius(for: CGRect(x: 0, y: 0, width: 20, height: 400)) == 12)
        #expect(BlurRenderer.radius(for: CGRect(x: 0, y: 0, width: 100, height: 400)) == 25)
        #expect(BlurRenderer.radius(for: CGRect(x: 0, y: 0, width: 1000, height: 400)) == 40)
    }

    @Test func blurRenderRectStaysInImage() {
        let rect = BlurRenderer.renderRect(for: CGRect(x: -10, y: 5.5, width: 30, height: 200), imageSize: CGSize(width: 100, height: 50))
        #expect(rect == CGRect(x: 0, y: 5, width: 20, height: 45))
    }

    @Test func blurCacheReturnsSameImage() {
        let base = makeImage(width: 64, height: 64, split: true)
        let rect = CGRect(x: 8, y: 8, width: 40, height: 40)
        let first = BlurRenderer.shared.blurredImage(of: base, in: rect)
        let second = BlurRenderer.shared.blurredImage(of: base, in: rect)
        #expect(first != nil)
        #expect(first === second)
        #expect(first?.width == 40 && first?.height == 40)
    }
}

struct HexColorTests {
    @Test func parsesAndFormats() {
        let rgb = HexColor.rgb(from: "#FF3B30")
        #expect(rgb == HexColor.RGB(red: 1, green: 59.0 / 255, blue: 48.0 / 255))
        #expect(HexColor.hex(from: rgb!) == "#FF3B30")
        #expect(HexColor.rgb(from: "00ff00") == HexColor.RGB(red: 0, green: 1, blue: 0))
    }

    @Test func rejectsInvalidHex() {
        #expect(HexColor.rgb(from: "#FFF") == nil)
        #expect(HexColor.rgb(from: "#GG0000") == nil)
        #expect(HexColor.rgb(from: "") == nil)
    }
}
