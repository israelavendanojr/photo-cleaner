import XCTest

/// Flattening a Live Photo from the full-screen viewer (JUN-79): it keeps the card with a flatten queued in the
/// bin's Flattens section, where swiping it away cancels it and clearing the bin makes the still. The mock
/// deck's first card is a Live Photo.
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
