import XCTest

/// Press and hold in the full-screen video plays at 2x, then goes back to how it was.
/// XCUITest can't look while a press is held, so these check what the hold leaves behind.
final class VideoBoostUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testHoldingPausedVideoPlaysThenPausesAgain() throws {
        let app = launch()
        let scrubber = openVideo(app)

        if onScreen(app, "Pause").exists { tapCenter(onScreen(app, "Pause")) }
        XCTAssertTrue(onScreen(app, "Play").waitForExistence(timeout: 5))
        rewind(scrubber)
        XCTAssertTrue(onScreen(app, "Play").waitForExistence(timeout: 5), "Still paused after rewinding")
        let before = scrubber.value as? String

        hold(app, for: 1.2)
        XCTAssertNotEqual(scrubber.value as? String, before, "Holding plays the paused video")
        XCTAssertTrue(onScreen(app, "Play").waitForExistence(timeout: 2), "Letting go pauses it again")
        XCTAssertTrue(onScreen(app, "Play").isHittable, "A hold isn't a tap: the controls stay up")
        XCTAssertFalse(speedPill(app).exists, "The 2x pill goes away on release")

        // Held and then dragged down: the drag wins and closes, as usual.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 3), "Dragging after a hold still closes")
        XCTAssertTrue(emptyPile(app).exists, "Holding decides nothing")
    }

    @MainActor
    func testHoldingPlayingVideoKeepsPlaying() throws {
        let app = launch()
        let scrubber = openVideo(app)
        rewind(scrubber)
        if onScreen(app, "Play").exists { tapCenter(onScreen(app, "Play")) }
        XCTAssertTrue(onScreen(app, "Pause").waitForExistence(timeout: 5))

        hold(app, for: 0.8)
        attachScreenshot(app, "after hold")
        XCTAssertTrue(onScreen(app, "Pause").exists, "Still playing after letting go")
        XCTAssertFalse(speedPill(app).exists)
        XCTAssertTrue(scrubber.isHittable, "The controls stay up")
    }

    @MainActor
    func testShortTapStillTogglesControls() throws {
        let app = launch()
        let scrubber = openVideo(app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 5), "A tap hides the controls")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5), "And shows them again")
    }

    // MARK: Helpers

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockLibrary", "YES", "-hasSeenSwipeHint", "YES", "-startAt", "video"]
        app.launch()
        return app
    }

    /// Opens the video card full screen and waits for playback. Returns the timeline.
    private func openVideo(_ app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Video, ")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let scrubber = app.descendants(matching: .any)["videoScrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3))
        // The clip is 8 s, so on a slow machine it may already have played to the end.
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label IN %@", ["Play", "Pause"]),
            object: app.buttons.matching(NSPredicate(format: "identifier IN %@", ["play.fill", "pause.fill"])).firstMatch
        )
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 10), .completed, "The controls show")
        return scrubber
    }

    /// The mock clip is short: back to the start so there's room to play.
    private func rewind(_ scrubber: XCUIElement) {
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)))
    }

    /// Above the middle, clear of the timeline and buttons.
    private func hold(_ app: XCUIApplication, for seconds: TimeInterval) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: seconds)
    }

    private func speedPill(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["video.speedPill"]
    }

    /// The cover leaves the feed's buttons in the tree underneath; prefer the one on top.
    private func onScreen(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.last { $0.isEnabled && $0.isHittable } ?? matches.last { $0.isEnabled } ?? matches.last ?? app.buttons[label]
    }

    private func emptyPile(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "0 MB ")).firstMatch
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
}
