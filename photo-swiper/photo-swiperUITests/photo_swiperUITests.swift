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

    @MainActor
    func testBatchOneByOneClearsOnlyDeletedItems() throws {
        let app = launch("-startAt", "batch")
        XCTAssertTrue(element(app, containing: "15 of 50").waitForExistence(timeout: 5))
        attachScreenshot(app, "batch card")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(element(app, containing: "1 of 14").waitForExistence(timeout: 3))
        attachScreenshot(app, "drill-in")

        drag(app, to: CGVector(dx: 0.02, dy: 0.5))
        XCTAssertTrue(element(app, containing: "2 of 14").waitForExistence(timeout: 3))
        tapCenter(onScreen(app, "Undo"))
        XCTAssertTrue(element(app, containing: "1 of 14").waitForExistence(timeout: 3))

        for _ in 0..<3 { tapAndWait(onScreen(app, "Delete")) }
        attachScreenshot(app, "after three deletes")
        for _ in 0..<11 { tapAndWait(onScreen(app, "Keep")) }

        XCTAssertTrue(element(app, containing: "16 of 50").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, containing: "0 MB to clear").exists, "Deleted items join the pile")
        attachScreenshot(app, "back in feed")

        tapCenter(onScreen(app, "Undo"))
        XCTAssertTrue(element(app, containing: "15 of 50").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, containing: "0 MB to clear").waitForExistence(timeout: 3), "Undo restores the whole batch")
    }

    @MainActor
    func testClosingBatchReviewEarlyChangesNothing() throws {
        let app = launch("-startAt", "batch")
        XCTAssertTrue(element(app, containing: "15 of 50").waitForExistence(timeout: 5))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(element(app, containing: "1 of 14").waitForExistence(timeout: 3))
        tapAndWait(onScreen(app, "Delete"))
        XCTAssertTrue(element(app, containing: "2 of 14").waitForExistence(timeout: 3))
        tapCenter(onScreen(app, "Close"))

        XCTAssertTrue(element(app, containing: "of 14").waitForNonExistence(timeout: 3), "The review closes")
        XCTAssertTrue(element(app, containing: "15 of 50").exists)
        XCTAssertTrue(element(app, containing: "0 MB to clear").exists)
    }

    @MainActor
    func testVideoPreviewPlaysScrubsAndClosesWithoutDeciding() throws {
        let app = launch("-startAt", "video")
        XCTAssertTrue(element(app, containing: "Video ·").waitForExistence(timeout: 5))
        let position = element(app, containing: " of 50").label

        // The play button sits in the middle of the card.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let scrubber = app.descendants(matching: .any)["videoScrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3))
        let pause = onScreen(app, "Pause")
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "Playback starts on open")
        sleep(1)
        attachScreenshot(app, "playing")

        tapCenter(pause)
        XCTAssertTrue(onScreen(app, "Play").waitForExistence(timeout: 2))

        let before = scrubber.value as? String
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertNotEqual(scrubber.value as? String, before, "Dragging the timeline seeks")
        attachScreenshot(app, "scrubbed")

        tapCenter(onScreen(app, "Close"))
        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 3), "The preview closes")
        XCTAssertTrue(element(app, containing: position).exists, "Watching doesn't move the feed")
        XCTAssertTrue(element(app, containing: "0 MB to clear").exists, "Watching decides nothing")
    }

    @MainActor
    func testPhotoPreviewOpensZoomsAndClosesWithoutDeciding() throws {
        let app = launch()
        XCTAssertTrue(element(app, containing: "1 of 50").waitForExistence(timeout: 5))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let preview = app.descendants(matching: .any)["photoPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        attachScreenshot(app, "fit")

        preview.doubleTap()
        sleep(1)
        attachScreenshot(app, "zoomed")

        tapCenter(onScreen(app, "Close"))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "The preview closes")
        XCTAssertTrue(element(app, containing: "1 of 50").exists, "Looking doesn't move the feed")
        XCTAssertTrue(element(app, containing: "0 MB to clear").exists, "Looking decides nothing")
    }

    @MainActor
    func testPendingPileDeletesByDefaultAndKeepsUnmarked() throws {
        let app = launch()
        XCTAssertTrue(element(app, containing: "1 of 20").waitForExistence(timeout: 5))
        for next in 2...4 {
            drag(app, to: CGVector(dx: 0.02, dy: 0.5))
            XCTAssertTrue(element(app, containing: "\(next) of 20").waitForExistence(timeout: 3))
        }

        tapCenter(element(app, containing: "to clear"))
        let tiles = app.descendants(matching: .any).matching(identifier: "pendingTile")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 3), "The pile shows the deleted photos")
        XCTAssertEqual(tiles.count, 3)
        let bin = app.buttons["binButton"]
        let keep = app.buttons["keepButton"]
        XCTAssertTrue(bin.waitForExistence(timeout: 3))
        XCTAssertTrue(bin.label.hasPrefix("Delete 3"), "Everything starts marked to delete")
        XCTAssertFalse(keep.exists, "Nothing to keep yet")

        tiles.element(boundBy: 0).tap()
        XCTAssertTrue(keep.waitForExistence(timeout: 3), "Unmarking offers to keep it")
        XCTAssertEqual(keep.label, "Keep 1")
        XCTAssertTrue(bin.label.hasPrefix("Delete 2"))
        attachScreenshot(app, "keep and delete")

        keep.tap()
        XCTAssertTrue(keep.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tiles.count, 2, "Kept photos leave the pile")

        bin.tap()
        let confirm = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        XCTAssertTrue(element(app, containing: "Nothing marked to clear").waitForExistence(timeout: 3))
        app.buttons["Done"].tap()

        XCTAssertTrue(element(app, containing: "0 MB to clear").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, containing: "4 of 20").exists, "The pile doesn't move the feed")
    }

    // MARK: Helpers

    /// The full-screen batch review leaves the feed's buttons in the tree underneath it.
    /// Prefer an enabled match (the feed's Undo is disabled behind the review); tapping its
    /// center skips the scroll-to-visible step that fails on covered elements.
    private func onScreen(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.last { $0.isEnabled } ?? matches.last ?? app.buttons[label]
    }

    private func tapAndWait(_ button: XCUIElement) {
        tapCenter(button)
        // Let the fly-out finish before the next card accepts input.
        usleep(550_000)
    }

    private func tapCenter(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
