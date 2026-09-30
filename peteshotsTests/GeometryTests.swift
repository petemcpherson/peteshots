import CoreGraphics
import Testing
@testable import peteshots

struct GeometryTests {
    @Test func distanceToSegmentInteriorAndEnds() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 10, y: 0)
        #expect(Geometry.distance(from: CGPoint(x: 5, y: 3), toSegment: a, b) == 3)
        #expect(Geometry.distance(from: CGPoint(x: -3, y: 4), toSegment: a, b) == 5)
        #expect(Geometry.distance(from: CGPoint(x: 13, y: 4), toSegment: a, b) == 5)
    }

    @Test func distanceToZeroLengthSegment() {
        let a = CGPoint(x: 2, y: 2)
        #expect(Geometry.distance(from: CGPoint(x: 5, y: 6), toSegment: a, a) == 5)
    }

    @Test func rectFromPointsIsNormalized() {
        let rect = Geometry.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 4, y: 5))
        #expect(rect == CGRect(x: 4, y: 5, width: 6, height: 15))
    }

    @Test func handlePositionsTopLeftOrigin() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(Geometry.RectHandle.topLeft.point(in: rect) == CGPoint(x: 0, y: 0))
        #expect(Geometry.RectHandle.bottom.point(in: rect) == CGPoint(x: 50, y: 50))
        #expect(Geometry.RectHandle.right.point(in: rect) == CGPoint(x: 100, y: 25))
        #expect(Geometry.RectHandle.allCases.count == 8)
    }

    @Test func handleHitTesting() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(Geometry.handle(at: CGPoint(x: 98, y: 52), in: rect, radius: 4) == .bottomRight)
        #expect(Geometry.handle(at: CGPoint(x: 50, y: 1), in: rect, radius: 4) == .top)
        #expect(Geometry.handle(at: CGPoint(x: 30, y: 25), in: rect, radius: 4) == nil)
    }

    @Test func resizeKeepsOppositeEdgeAndMinimumSize() {
        let rect = CGRect(x: 10, y: 10, width: 100, height: 100)
        let min = CGSize(width: 8, height: 8)
        let grown = Geometry.resize(rect, handle: .topLeft, to: CGPoint(x: 0, y: 5), minSize: min)
        #expect(grown == CGRect(x: 0, y: 5, width: 110, height: 105))

        let collapsed = Geometry.resize(rect, handle: .right, to: CGPoint(x: -50, y: 0), minSize: min)
        #expect(collapsed == CGRect(x: 10, y: 10, width: 8, height: 100))
    }

    @Test func clampRectShiftsInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let shifted = Geometry.clampRect(CGRect(x: 180, y: -10, width: 50, height: 30), to: bounds)
        #expect(shifted == CGRect(x: 150, y: 0, width: 50, height: 30))

        let shrunk = Geometry.clampRect(CGRect(x: -10, y: 0, width: 300, height: 30), to: bounds)
        #expect(shrunk == CGRect(x: 0, y: 0, width: 200, height: 30))
    }

    @Test func annotationOffsetAndHitTest() {
        let arrow = Annotation.arrow(ArrowAnnotation(start: .zero, end: CGPoint(x: 100, y: 0), colorHex: "#FF0000", strokeWidth: 4))
        #expect(arrow.contains(CGPoint(x: 50, y: 9), tolerance: 8))
        #expect(!arrow.contains(CGPoint(x: 50, y: 11), tolerance: 8))

        guard case .arrow(let moved) = arrow.offsetBy(dx: 5, dy: 7) else {
            Issue.record("Expected an arrow")
            return
        }
        #expect(moved.start == CGPoint(x: 5, y: 7))
        #expect(moved.end == CGPoint(x: 105, y: 7))
        #expect(moved.id == arrow.id)
    }
}
