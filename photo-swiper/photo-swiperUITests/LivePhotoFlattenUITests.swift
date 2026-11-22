import XCTest

/// Flattening a Live Photo from the full-screen viewer (JUN-79): it keeps the card with a flatten queued in the
/// bin's Flattens section, where swiping it away cancels it and clearing the bin makes the still. Picking
/// another frame from the strip turns it into Change & Flatten (JUN-106). The mock deck's first card is a
/// Live Photo.
final class LivePhotoFlattenUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // XCTest runs setUp on the main thread.
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testFlatteningKeepsTheCardAndOffersUndo() throws {
        let app = launch()
        let position = topCard(app)
        openTopCard(app)
        let flatten = app.buttons["photo.flatten"]
        XCTAssertTrue(flatten.waitForExistence(timeout: 3), "A Live Photo offers Flatten")
        XCTAssertTrue(app.descendants(matching: .any)["photo.flattenSummary"].label.contains("saves"), "It says what it saves")
        attachScreenshot(app, "flatten bar")

        flatten.tap()

        let toast = app.descendants(matching: .any)["feed.trimToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Flatten queued"), "The toast names the flatten: \(toast.label)")
        XCTAssertTrue(waitForTopCard(app, not: position), "The photo counts as kept and the feed moves on")

        toast.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForTopCard(app, is: position), "Undo brings it back")
    }

    @MainActor
    func testTheBinListsTheFlattenAndSwipingItAwayCancelsIt() throws {
        let app = launch()
        flattenTopCard(app)

        tapCenter(element(app, containing: "to clear"))
        let row = app.descendants(matching: .any)["pile.flattenRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Flattens has the photo")
        XCTAssertTrue(app.staticTexts["Flattens"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["pile.editRow"].exists, "Not under Edits")
        XCTAssertTrue(app.buttons["binButton"].label.hasPrefix("Clear bin"))
        attachScreenshot(app, "flattens section")

        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: -0.4, dy: 0.5)))
        XCTAssertTrue(row.waitForNonExistence(timeout: 3), "Swiping it away cancels the flatten")
    }

    @MainActor
    func testClearingTheBinMakesTheStill() throws {
        let app = launch()
        flattenTopCard(app)

        tapCenter(element(app, containing: "to clear"))
        let bin = app.buttons["binButton"]
        XCTAssertTrue(bin.waitForExistence(timeout: 3))
        bin.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.label.contains("Clear the bin") || alert.staticTexts["Clear the bin?"].exists)
        XCTAssertTrue(element(app, containing: "1 flattened photo").exists, "The confirm names the flatten")
        app.alerts.buttons["Clear"].tap()

        let freed = element(app, containing: "Freed ")
        XCTAssertTrue(freed.waitForExistence(timeout: 10), "The bin says what was freed")
    }

    // MARK: Picking another key photo (JUN-106)

    @MainActor
    func testPickingAnotherFrameOffersChangeAndFlattenAndResetGoesBack() throws {
        let app = launch()
        openTopCard(app)
        let flatten = app.buttons["photo.flatten"]
        XCTAssertTrue(flatten.waitForExistence(timeout: 3))
        pickEarlyFrame(app)

        XCTAssertTrue(waitForLabel(flatten, "Change & Flatten"), "Another frame always flattens: \(flatten.label)")
        XCTAssertTrue(app.descendants(matching: .any)["photo.frameNote"].exists, "It says the frame is lower resolution")
        attachScreenshot(app, "change and flatten")

        app.buttons["photo.frameReset"].tap()
        XCTAssertTrue(waitForLabel(flatten, "Flatten"), "Reset goes back to the key photo")
        XCTAssertFalse(app.descendants(matching: .any)["photo.frameNote"].exists)
    }

    @MainActor
    func testLeavingWithAnotherFramePickedAsksFirst() throws {
        let app = launch()
        let position = topCard(app)
        openTopCard(app)
        XCTAssertTrue(app.buttons["photo.flatten"].waitForExistence(timeout: 3))
        pickEarlyFrame(app)
        XCTAssertTrue(waitForLabel(app.buttons["photo.flatten"], "Change & Flatten"))

        closeButton(app).tap()
        XCTAssertTrue(app.staticTexts["Save changes?"].waitForExistence(timeout: 3), "Leaving asks first")
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["photoPreview"].exists, "Keep editing stays")

        closeButton(app).tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 3))
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["photoPreview"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForTopCard(app, is: position), "Discarding decides nothing")
    }

    @MainActor
    func testADecisionSwipeWithAnotherFramePickedAsksAndDiscardDecidesAsSwiped() throws {
        let app = launch()
        let position = topCard(app)
        openTopCard(app)
        XCTAssertTrue(app.buttons["photo.flatten"].waitForExistence(timeout: 3))
        pickEarlyFrame(app)
        XCTAssertTrue(waitForLabel(app.buttons["photo.flatten"], "Change & Flatten"))

        app.descendants(matching: .any)["photoPreview"].swipeLeft()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 3), "A decision swipe asks first too")
        app.buttons["Discard"].tap()

        XCTAssertTrue(waitForTopCard(app, not: position))
        tapCenter(element(app, containing: "to clear"))
        XCTAssertTrue(app.descendants(matching: .any)["pendingTile"].waitForExistence(timeout: 3), "Binned, as swiped")
        XCTAssertFalse(app.descendants(matching: .any)["pile.flattenRow"].exists, "Nothing flattened")
    }

    @MainActor
    func testADecisionSwipeWithAnotherFramePickedCanSaveTheFlattenInstead() throws {
        let app = launch()
        let position = topCard(app)
        openTopCard(app)
        XCTAssertTrue(app.buttons["photo.flatten"].waitForExistence(timeout: 3))
        pickEarlyFrame(app)
        XCTAssertTrue(waitForLabel(app.buttons["photo.flatten"], "Change & Flatten"))

        app.descendants(matching: .any)["photoPreview"].swipeLeft()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 3))
        app.buttons["Save changes"].tap()

        XCTAssertTrue(waitForTopCard(app, not: position))
        tapCenter(element(app, containing: "to clear"))
        XCTAssertTrue(app.descendants(matching: .any)["pile.flattenRow"].waitForExistence(timeout: 3), "Kept and flattened")
        XCTAssertFalse(app.descendants(matching: .any)["pendingTile"].exists, "Not binned")
    }

    @MainActor
    func testChangeAndFlattenQueuesTheChosenFrame() throws {
        let app = launch()
        let position = topCard(app)
        openTopCard(app)
        let flatten = app.buttons["photo.flatten"]
        XCTAssertTrue(flatten.waitForExistence(timeout: 3))
        pickEarlyFrame(app)
        XCTAssertTrue(waitForLabel(flatten, "Change & Flatten"))

        flatten.tap()
        XCTAssertTrue(waitForTopCard(app, not: position), "Queued like Flatten, and the feed moves on")

        tapCenter(element(app, containing: "to clear"))
        let row = app.descendants(matching: .any)["pile.flattenRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.label.contains("new key photo"), "The row names the new key photo: \(row.label)")
        attachScreenshot(app, "flattens row with a chosen frame")
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockLibrary", "YES", "-resetProgress", "YES", "-hasSeenSwipeHint", "YES", "-resetTunables", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func openTopCard(_ app: XCUIApplication) {
        _ = topCard(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["photoPreview"].waitForExistence(timeout: 3), "The photo opens full screen")
    }

    @MainActor
    private func flattenTopCard(_ app: XCUIApplication) {
        let position = topCard(app)
        openTopCard(app)
        let flatten = app.buttons["photo.flatten"]
        XCTAssertTrue(flatten.waitForExistence(timeout: 3))
        flatten.tap()
        XCTAssertTrue(waitForTopCard(app, not: position))
    }

    /// Taps the frame strip near its start, well before the key photo (1.25 s into the mock motion).
    @MainActor
    private func pickEarlyFrame(_ app: XCUIApplication) {
        let strip = app.descendants(matching: .any)["videoScrubber"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "The frame strip shows")
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
    }

    @MainActor
    private func closeButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["photo.close"]
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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

    @MainActor
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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
