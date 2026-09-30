import CoreGraphics
import Testing
@testable import peteshots

struct TextLayoutTests {
    private func text(_ string: String, fontSize: CGFloat = 20) -> TextAnnotation {
        TextAnnotation(origin: CGPoint(x: 10, y: 10), string: string, fontSize: fontSize, colorHex: "#FF0000")
    }

    @Test func countsLinesByNewlines() {
        #expect(TextLayout.lineCount(of: "") == 1)
        #expect(TextLayout.lineCount(of: "one") == 1)
        #expect(TextLayout.lineCount(of: "one\ntwo") == 2)
        #expect(TextLayout.lineCount(of: "one\n") == 2)
    }

    @Test func heightIsLinesTimesLineHeight() {
        let size = TextLayout.size(of: text("one\ntwo\nthree"))
        #expect(size.height == 3 * 20 * TextLayout.lineHeightMultiple)
        #expect(size.width > 0)
    }

    @Test func widthDoesNotWrap() {
        let short = TextLayout.size(of: text("Hello"))
        let long = TextLayout.size(of: text("Hello Hello Hello Hello Hello Hello Hello Hello"))
        #expect(long.width > short.width * 5)
        #expect(long.height == short.height)
    }

    @Test func cornerResizeScalesFontAndKeepsOppositeCorner() {
        let original = text("Hello\nWorld")
        let frame = TextLayout.frame(of: original)
        let target = CGPoint(x: frame.maxX, y: frame.minY + frame.height * 2)
        let resized = TextLayout.resize(original, corner: .bottomRight, to: target)
        #expect(abs(resized.fontSize - 40) < 0.001)
        #expect(resized.origin == original.origin)

        // Dragging the top-left corner keeps the bottom-right corner fixed.
        let fromTopLeft = TextLayout.resize(original, corner: .topLeft, to: CGPoint(x: frame.minX, y: frame.maxY - frame.height * 2))
        let newFrame = TextLayout.frame(of: fromTopLeft)
        #expect(abs(newFrame.maxX - frame.maxX) < 0.001)
        #expect(abs(newFrame.maxY - frame.maxY) < 0.001)
    }

    @Test func resizeClampsToMinimumFontSize() {
        let original = text("Hello")
        let resized = TextLayout.resize(original, corner: .bottomRight, to: original.origin)
        #expect(resized.fontSize == TextLayout.minFontSize)
    }

    @Test func textHitTestUsesFrame() {
        let annotation = Annotation.text(text("Hello"))
        let frame = TextLayout.frame(of: text("Hello"))
        #expect(annotation.contains(CGPoint(x: frame.midX, y: frame.midY), tolerance: 0))
        #expect(!annotation.contains(CGPoint(x: frame.maxX + 20, y: frame.midY), tolerance: 0))
        #expect(annotation.handlePoints.count == 4)
    }

    @Test func drawTextPaintsInsideFrame() {
        let context = CGContext(
            data: nil, width: 120, height: 60, bitsPerComponent: 8, bytesPerRow: 120 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
        context.translateBy(x: 0, y: 60)
        context.scaleBy(x: 1, y: -1)

        let annotation = TextAnnotation(origin: CGPoint(x: 5, y: 5), string: "HHHH", fontSize: 30, colorHex: "#FF0000")
        AnnotationDrawing.drawText(annotation, in: context)

        let frame = TextLayout.frame(of: annotation)
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        var redInside = 0
        var changedOutside = 0
        for y in 0..<60 {
            for x in 0..<120 {
                let offset = y * context.bytesPerRow + x * 4
                let isRed = data[offset] > 200 && data[offset + 1] < 60
                let isWhite = data[offset] > 250 && data[offset + 1] > 250 && data[offset + 2] > 250
                let inside = frame.insetBy(dx: -2, dy: -2).contains(CGPoint(x: x, y: y))
                if inside, isRed { redInside += 1 }
                if !inside, !isWhite { changedOutside += 1 }
            }
        }
        #expect(redInside > 100)
        #expect(changedOutside == 0)
    }
}
