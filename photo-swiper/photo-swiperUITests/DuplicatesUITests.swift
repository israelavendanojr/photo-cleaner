import XCTest

/// The duplicates card on the mock deck (`-startAt duplicates`): three copies of one photo.
final class DuplicatesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTheCardNamesTheCopiesAndDeleteKeepsOne() throws {
        let app = launch("-startAt", "duplicates")
        let hero = app.descendants(matching: .any)["duplicates.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "3 copies").exists)
        XCTAssertFalse(element(app, containing: "of the same photo").exists)
        XCTAssertEqual(hero.label, "Copy to keep", "No saved date or reason on the hero")
        XCTAssertTrue(app.buttons["Open copy 2"].exists, "No saved date on the thumbnails")
        XCTAssertFalse(element(app, containing: "Highest resolution").exists, "The keeper's reason isn't shown")
        XCTAssertTrue(element(app, containing: "The other two copies can go.").exists)
        XCTAssertTrue(element(app, containing: "Keep one, clear 2").exists)
        let card = topCard(app)
        attachScreenshot(app, "duplicates card")

        app.buttons["Delete"].tap()

        XCTAssertTrue(waitForTopCard(app, not: card), "One swipe settles the whole set")
        XCTAssertFalse(emptyPile(app).exists, "The two other copies join the pile")
    }

    @MainActor
    func testTappingTheCardOpensTheCopiesOneByOne() throws {
        let app = launch("-startAt", "duplicates")
        let hero = app.descendants(matching: .any)["duplicates.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))

        hero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(element(app, containing: "Duplicates").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, containing: "1 of 3").exists)
        let marker = app.descendants(matching: .any)["review.bestPick"]
        XCTAssertTrue(marker.waitForExistence(timeout: 3))
        XCTAssertEqual(marker.label, "best pick", "Opens on the copy to keep")
        XCTAssertFalse(element(app, containing: "Highest resolution").exists, "No reason is read out")
        attachScreenshot(app, "duplicates review")
    }

    // MARK: Helpers

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockLibrary", "YES", "-hasSeenSwipeHint", "YES", "-resetTunables", "YES"] + arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The "to clear" counter at zero.
    private func emptyPile(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "0 MB ")).firstMatch
    }

    /// The debug marker naming the top card by id.
    private func topCard(_ app: XCUIApplication) -> String {
        let marker = app.descendants(matching: .any)["feed.currentCard"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "The feed shows")
        return marker.label
    }

    private func waitForTopCard(_ app: XCUIApplication, not id: String, timeout: TimeInterval = 3) -> Bool {
        let marker = app.descendants(matching: .any)["feed.currentCard"]
        let predicate = NSPredicate(format: "exists == true AND label != %@", id)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: marker)], timeout: timeout) == .completed
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
