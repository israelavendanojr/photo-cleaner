import XCTest

/// Trimming in the full-screen video (JUN-7): moving a handle shows what the trim saves, leaving with
/// the handles moved asks first, and saving keeps the card with the trim queued in the bin.
final class VideoTrimUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testUntouchedHandlesCloseWithoutAsking() throws {
        let app = launch()
        let scrubber = openVideo(app)
        XCTAssertTrue(trimStart(app).waitForExistence(timeout: 5), "The mock clip is long enough to trim")
        XCTAssertFalse(summary(app).exists, "No summary before a handle moves")

        tapCenter(onScreen(app, "Close"))
        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 3), "Closes at once")
    }

    @MainActor
    func testLeavingWithAMovedHandleAsksFirst() throws {
        let app = launch()
        let position = topCard(app)
        let scrubber = openVideo(app)
        moveStartHandle(app, scrubber: scrubber)
        XCTAssertTrue(summary(app).waitForExistence(timeout: 2), "Moving a handle shows what it saves")
        XCTAssertTrue((summary(app).label).contains("saves ~"))
        attachScreenshot(app, "trimmed")

        tapCenter(onScreen(app, "Close"))
        let keepEditing = app.buttons["Keep editing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 2), "Closing asks first")
        attachScreenshot(app, "asking")
        keepEditing.tap()
        XCTAssertTrue(scrubber.exists, "Keep editing stays")
        XCTAssertTrue(summary(app).exists, "and keeps the handles")

        swipeDown(app)
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 2), "Swiping down asks too")
        discard.tap()
        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 3), "Discard closes")
        XCTAssertTrue(waitForTopCard(app, is: position), "Discarding decides nothing")
        XCTAssertTrue(emptyPile(app).exists)
    }

    @MainActor
    func testSavingATrimKeepsTheCardAndOffersUndo() throws {
        let app = launch()
        let position = topCard(app)
        let scrubber = openVideo(app)
        moveStartHandle(app, scrubber: scrubber)
        let save = app.descendants(matching: .any)["video.trimSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 2))

        tapCenter(save)

        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 3), "Trim closes the viewer")
        let toast = app.descendants(matching: .any)["feed.trimToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3), "A toast says the trim is queued")
        XCTAssertTrue(waitForTopCard(app, not: position), "The video counts as kept and the feed moves on")
        attachScreenshot(app, "queued")

        // The toast hides itself after a few seconds; its Undo is at its trailing end.
        toast.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForTopCard(app, is: position), "Undo brings the video back")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 2), "and the toast goes")
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockLibrary", "YES", "-hasSeenSwipeHint", "YES", "-resetTunables", "YES", "-startAt", "video"]
        app.launch()
        return app
    }

    @MainActor
    private func openVideo(_ app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Video, ")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let scrubber = app.descendants(matching: .any)["videoScrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3))
        return scrubber
    }

    @MainActor
    private func trimStart(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["video.trimStart"]
    }

    @MainActor
    private func summary(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["video.trimSummary"]
    }

    /// Drags the start handle about a third of the way in.
    @MainActor
    private func moveStartHandle(_ app: XCUIApplication, scrubber: XCUIElement) {
        let handle = trimStart(app)
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)))
    }

    @MainActor
    private func cardMarker(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["feed.currentCard"]
    }

    @MainActor
    private func topCard(_ app: XCUIApplication) -> String {
        let marker = cardMarker(app)
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "The feed shows")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label != %@", "none"), object: marker)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 5), .completed)
        return marker.label
    }

    @MainActor
    private func waitForTopCard(_ app: XCUIApplication, is id: String, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", id), object: cardMarker(app))
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForTopCard(_ app: XCUIApplication, not id: String, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", id), object: cardMarker(app))
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The cover leaves the feed's buttons in the tree underneath; prefer the one on top.
    @MainActor
    private func onScreen(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.last { $0.isEnabled && $0.isHittable } ?? matches.last { $0.isEnabled } ?? matches.last ?? app.buttons[label]
    }

    @MainActor
    private func emptyPile(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "0 MB ")).firstMatch
    }

    /// Through the upper part of the screen, clear of the strip.
    @MainActor
    private func swipeDown(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
    }

    @MainActor
    private func tapCenter(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
