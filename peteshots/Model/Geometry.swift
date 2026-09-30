//
//  Geometry.swift
//  peteshots
//

import CoreGraphics

/// Hit-testing, handle, and clamping helpers. All values are in one space
/// (usually image pixels, top-left origin); nothing here converts spaces.
nonisolated enum Geometry {
    /// The 8 resize handles of a rectangle, in a top-left origin space.
    enum RectHandle: CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
            case .top: CGPoint(x: rect.midX, y: rect.minY)
            case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
            case .right: CGPoint(x: rect.maxX, y: rect.midY)
            case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
            case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
            case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
            case .left: CGPoint(x: rect.minX, y: rect.midY)
            }
        }

        var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
        var movesMinY: Bool { self == .topLeft || self == .top || self == .topRight }
        var movesMaxY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    }

    static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Shortest distance from `point` to the segment `a`–`b`.
    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = clamp(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0, 1)
        return distance(point, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// The rect with positive width and height spanning two corner points.
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// The handle within `radius` of `point`, if any. Corners win over edges.
    static func handle(at point: CGPoint, in rect: CGRect, radius: CGFloat) -> RectHandle? {
        let ordered: [RectHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft, .top, .right, .bottom, .left]
        return ordered.first { distance($0.point(in: rect), point) <= radius }
    }

    /// Moves the edges that `handle` controls to `point`. The opposite edges stay
    /// fixed, and each side keeps at least `minSize`.
    static func resize(_ rect: CGRect, handle: RectHandle, to point: CGPoint, minSize: CGSize) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesMinX { minX = min(point.x, maxX - minSize.width) }
        if handle.movesMaxX { maxX = max(point.x, minX + minSize.width) }
        if handle.movesMinY { minY = min(point.y, maxY - minSize.height) }
        if handle.movesMaxY { maxY = max(point.y, minY + minSize.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Shifts `rect` so it lies inside `bounds`, shrinking it only if it is larger.
    static func clampRect(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = clamp(rect.minX, bounds.minX, bounds.maxX - width)
        let y = clamp(rect.minY, bounds.minY, bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Clamps a point into `bounds`.
    static func clampPoint(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: clamp(point.x, bounds.minX, bounds.maxX), y: clamp(point.y, bounds.minY, bounds.maxY))
    }
}
