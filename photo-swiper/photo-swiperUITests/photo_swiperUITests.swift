//
//  photo_swiperUITests.swift
//  photo-swiperUITests
//
//  Created by Israel Avendano Jr. on 10/7/26.
//

import XCTest

/// Drives the real swipe gesture and buttons against the mock session.
final class photo_swiperUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSwipeLeftAddsToPileAndUndoRestores() throws {
        let app = launch()
        XCTAssertTrue(element(app, containing: "1 of 50").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "0 MB to clear").exists)

        drag(app, to: CGVector(dx: 0.02, dy: 0.5))

        XCTAssertTrue(element(app, containing: "2 of 50").waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, containing: "0 MB to clear").exists, "Delete should add to the pile")

        app.buttons["Undo"].tap()

        XCTAssertTrue(element(app, containing: "1 of 50").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, containing: "0 MB to clear").waitForExistence(timeout: 3))
    }

    @MainActor
    func testShortDragSnapsBack() throws {
        let app = launch()
        XCTAssertTrue(element(app, containing: "1 of 50").waitForExistence(timeout: 5))

        drag(app, to: CGVector(dx: 0.4, dy: 0.5), hold: 0.4)

        sleep(1)
        XCTAssertTrue(element(app, containing: "1 of 50").exists, "A short drag must not commit")
    }

    @MainActor
    func testSwipeUpIsLaterAndRightIsKeep() throws {
        let app = launch()
        XCTAssertTrue(element(app, containing: "1 of 50").waitForExistence(timeout: 5))

        drag(app, to: CGVector(dx: 0.5, dy: 0.1))
        XCTAssertTrue(element(app, containing: "2 of 50").waitForExistence(timeout: 3))

        drag(app, to: CGVector(dx: 0.98, dy: 0.5))
        XCTAssertTrue(element(app, containing: "3 of 50").waitForExistence(timeout: 3))

        XCTAssertTrue(element(app, containing: "0 MB to clear").exists, "Later and Keep never add to the pile")
    }

    @MainActor
    func testSimilarToggleThenDeleteButton() throws {
        let app = launch("-startAt", "similar")
        let shot = app.buttons["Shot 2"]
        XCTAssertTrue(shot.waitForExistence(timeout: 5))
        XCTAssertEqual(shot.value as? String, "Marked to clear")

        shot.tap()
        XCTAssertEqual(shot.value as? String, "Keeping")

        app.buttons["Delete"].tap()

        XCTAssertTrue(element(app, containing: "14 of 50").waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, containing: "0 MB to clear").exists)
    }

    // MARK: Helpers

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        // Always the mock library, so tests never hit the photo permission prompt.
        app.launchArguments = ["-mockLibrary", "YES"] + arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func drag(_ app: XCUIApplication, to target: CGVector, hold: TimeInterval = 0.05) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: hold, thenDragTo: app.coordinate(withNormalizedOffset: target))
    }
}
