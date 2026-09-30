import CoreGraphics
import Testing
@testable import peteshots

struct CoordinateSpaceTests {
    private let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func rectOnPrimaryScreen() {
        let cocoa = CGRect(x: 100, y: 700, width: 200, height: 100)
        let cg = CoordinateSpace.cgRect(fromCocoa: cocoa, primaryScreenFrame: primary)
        #expect(cg == CGRect(x: 100, y: 182, width: 200, height: 100))
    }

    @Test func fullPrimaryScreenMapsToOrigin() {
        let cg = CoordinateSpace.cgRect(fromCocoa: primary, primaryScreenFrame: primary)
        #expect(cg == primary)
    }

    @Test func rectOnScreenAbovePrimary() {
        // A display placed above the primary one has positive Cocoa y and negative CG y.
        let cocoa = CGRect(x: 0, y: 1000, width: 400, height: 300)
        let cg = CoordinateSpace.cgRect(fromCocoa: cocoa, primaryScreenFrame: primary)
        #expect(cg == CGRect(x: 0, y: -318, width: 400, height: 300))
    }

    @Test func rectOnScreenLeftOfPrimary() {
        let cocoa = CGRect(x: -1920, y: -98, width: 1920, height: 1080)
        let cg = CoordinateSpace.cgRect(fromCocoa: cocoa, primaryScreenFrame: primary)
        #expect(cg == CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    }
}
