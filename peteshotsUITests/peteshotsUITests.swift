//
//  peteshotsUITests.swift
//  peteshotsUITests
//

import XCTest

/// Smoke test: the menu bar app launches and keeps running.
final class peteshotsUITests: XCTestCase {
    @MainActor
    func testLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertNotEqual(app.state, .notRunning)
        app.terminate()
    }
}
