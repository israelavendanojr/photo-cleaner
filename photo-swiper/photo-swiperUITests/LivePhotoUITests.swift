import XCTest

/// Press and hold a Live Photo in the full-screen viewer to play it (JUN-105). The mock deck's first card
/// is a Live Photo. XCUITest can't look while a press is held, so these read the play count the viewer
/// leaves for them (`photo.livePlayCount`).
final class LivePhotoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // XCTest runs setUp on the main thread.
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testHoldingALivePhotoPlaysIt() throws {
        let app = launch()
        let preview = openTopCard(app)
        XCTAssertTrue(liveChip(app).waitForExistence(timeout: 3), "A Live Photo says so")
        XCTAssertEqual(playCount(app).label, "0")

        hold(app, for: 1.2)
        XCTAssertTrue(waitForPlayCount(app, atLeast: 1), "Holding plays the motion")
        attachScreenshot(app, "after hold")
        XCTAssertTrue(preview.exists, "Holding doesn't close or decide")
        XCTAssertTrue(emptyPile(app).exists, "Holding decides nothing")
        XCTAssertTrue(onScreen(app, "Close").isHittable, "A hold isn't a tap: the top bar stays up")
    }

    @MainActor
    func testAHoldThatBecomesADragStillCloses() throws {
        let app = launch()
        let preview = openTopCard(app)
        XCTAssertTrue(liveChip(app).waitForExistence(timeout: 3))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "Dragging after a hold still closes")
        XCTAssertTrue(emptyPile(app).exists, "Holding decides nothing")
    }

    @MainActor
    func testAPlainPhotoHasNoLiveChip() throws {
        let app = launch()
        let first = topCard(app)
        tapCenter(onScreen(app, "Keep"))
        XCTAssertTrue(waitForTopCard(app, isNot: first), "On to the second card, a plain photo")

        _ = openTopCard(app)
        sleep(1)
        XCTAssertFalse(liveChip(app).exists, "Plain photos look as before")
        hold(app, for: 1)
        XCTAssertEqual(playCount(app).label, "0", "Holding a plain photo plays nothing")
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockLibrary", "YES", "-resetProgress", "YES", "-hasSeenSwipeHint", "YES", "-resetTunables", "YES"]
        app.launch()
        return app
    }

    /// Opens the top card full screen and returns the viewer.
    @MainActor
    private func openTopCard(_ app: XCUIApplication) -> XCUIElement {
        _ = topCard(app)
        let preview = app.descendants(matching: .any)["photoPreview"]
        // The card's own button, which the caption can't cover at large text sizes.
        tapCenter(onScreen(app, "View full screen"))
        XCTAssertTrue(preview.waitForExistence(timeout: 3), "The photo opens full screen")
        return preview
    }

    @MainActor
    private func liveChip(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["photo.liveChip"]
    }

    @MainActor
    private func playCount(_ app: XCUIApplication) -> XCUIElement {
        let marker = app.descendants(matching: .any)["photo.livePlayCount"]
        XCTAssertTrue(marker.waitForExistence(timeout: 3))
        return marker
    }

    @MainActor
    private func waitForPlayCount(_ app: XCUIApplication, atLeast count: Int) -> Bool {
        let predicate = NSPredicate { element, _ in
            Int((element as? XCUIElement)?.label ?? "") ?? 0 >= count
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: playCount(app))], timeout: 5) == .completed
    }

    /// Above the middle, clear of the top bar.
    @MainActor
    private func hold(_ app: XCUIApplication, for seconds: TimeInterval) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: seconds)
    }

    @MainActor
    private func topCard(_ app: XCUIApplication) -> String {
        let marker = app.descendants(matching: .any)["feed.currentCard"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "The feed shows")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label != %@", "none"), object: marker)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 5), .completed)
        return marker.label
    }

    @MainActor
    private func waitForTopCard(_ app: XCUIApplication, isNot id: String) -> Bool {
        let marker = app.descendants(matching: .any)["feed.currentCard"]
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", id), object: marker)
        return XCTWaiter().wait(for: [moved], timeout: 3) == .completed
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
