import XCTest

/// Out of swipes, a swipe flies out like any other, then the same card rewinds into place and
/// the wall opens. Nothing is decided: the top card and the pile stay as they were.
final class SwipeRewindUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testRefusedDragRewindsThenGoesThroughAfterUnlock() throws {
        let app = launch("-swipesLeft", "0", "-unlocked", "NO")
        let first = topCard(app)
        let rest = cardFrame(app)
        XCTAssertTrue(emptyPile(app).exists)

        drag(app, to: CGVector(dx: 0.02, dy: 0.5))

        let unlock = app.buttons["paywall.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10), "The refused swipe opens the wall")
        XCTAssertEqual(cardMarker(app).label, first, "The same card came back")
        XCTAssertTrue(emptyPile(app).exists, "Nothing went to the pile")

        app.buttons["paywall.notNow"].tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 3))
        XCTAssertEqual(cardMarker(app).label, first)
        XCTAssertTrue(waitForRest(app, rest), "The card is back in place")

        // A right flick is refused the same way.
        drag(app, to: CGVector(dx: 0.98, dy: 0.5))
        XCTAssertTrue(unlock.waitForExistence(timeout: 10), "The next swipe asks again")
        XCTAssertEqual(cardMarker(app).label, first)

        unlock.tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 8), "The sheet closes")
        drag(app, to: CGVector(dx: 0.02, dy: 0.5))
        XCTAssertTrue(waitForTopCard(app, not: first), "Unlocked, the same card goes through")
        XCTAssertFalse(emptyPile(app).exists, "Delete adds to the pile")
    }

    @MainActor
    func testRefusedButtonSwipesRewindInEveryDirection() throws {
        let app = launch("-swipesLeft", "0", "-unlocked", "NO")
        let first = topCard(app)
        let rest = cardFrame(app)
        let unlock = app.buttons["paywall.unlock"]

        for button in ["Delete", "Later", "Keep"] {
            tapCenter(onScreen(app, button))
            XCTAssertTrue(unlock.waitForExistence(timeout: 10), "\(button) is refused and opens the wall")
            XCTAssertEqual(cardMarker(app).label, first, "\(button) left the card on top")
            XCTAssertTrue(emptyPile(app).exists, "\(button) added nothing to the pile")

            app.buttons["paywall.notNow"].tap()
            XCTAssertTrue(unlock.waitForNonExistence(timeout: 3))
            XCTAssertTrue(waitForRest(app, rest), "Back in place after \(button)")
        }
    }

    @MainActor
    func testShortDragAtZeroSwipesSnapsBackWithoutTheWall() throws {
        let app = launch("-swipesLeft", "0", "-unlocked", "NO")
        let first = topCard(app)
        let rest = cardFrame(app)

        // Above the card's center button: a drag released on it can open the photo full screen.
        drag(app, from: CGVector(dx: 0.5, dy: 0.3), to: CGVector(dx: 0.62, dy: 0.3), hold: 0.4)

        sleep(2)
        XCTAssertFalse(app.buttons["paywall.unlock"].exists, "A short drag isn't a swipe, so no wall")
        XCTAssertEqual(cardMarker(app).label, first)
        XCTAssertTrue(waitForRest(app, rest))
    }

    @MainActor
    func testSwipesDuringTheRewindAreIgnored() throws {
        let app = launch("-swipesLeft", "0", "-unlocked", "NO")
        let first = topCard(app)
        let unlock = app.buttons["paywall.unlock"]

        // Both buttons are found first, so the second tap lands mid-rewind.
        let delete = onScreen(app, "Delete")
        let keep = onScreen(app, "Keep")
        tapCenter(delete)
        tapCenter(keep)

        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        XCTAssertEqual(cardMarker(app).label, first)
        XCTAssertTrue(emptyPile(app).exists)

        app.buttons["paywall.notNow"].tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 3))
        sleep(2)
        XCTAssertFalse(unlock.exists, "No second refusal was queued behind the first")
        XCTAssertEqual(cardMarker(app).label, first)
    }

    // MARK: Helpers

    private func cardMarker(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["feed.currentCard"]
    }

    /// Waits for the feed, then names its top card.
    private func topCard(_ app: XCUIApplication) -> String {
        let marker = cardMarker(app)
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "The feed shows")
        XCTAssertTrue(waitForTopCard(app, not: "none", timeout: 10))
        // Let the first card settle before measuring it.
        sleep(1)
        return marker.label
    }

    private func waitForTopCard(_ app: XCUIApplication, not id: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND label != %@", id)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: cardMarker(app))
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The top card's frame, through its "View full screen" button: only the top card's is
    /// hittable. Waits a little, since a busy simulator can be slow to settle.
    private func cardFrame(_ app: XCUIApplication, timeout: TimeInterval = 5) -> CGRect {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", "View full screen"))
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            if let top = buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) { return top.frame }
            usleep(250_000)
        } while Date.now < deadline
        XCTFail("The top card shows")
        return .zero
    }

    /// Waits for the top card to sit where it was at rest, within a couple of points.
    private func waitForRest(_ app: XCUIApplication, _ rest: CGRect, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            let frame = cardFrame(app)
            if abs(frame.midX - rest.midX) < 2, abs(frame.midY - rest.midY) < 2 { return true }
            usleep(250_000)
        } while Date.now < deadline
        return false
    }

    /// A full-screen cover leaves the feed's buttons in the tree underneath; prefer a hittable one.
    private func onScreen(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.last { $0.isEnabled && $0.isHittable } ?? matches.last { $0.isEnabled } ?? matches.last ?? app.buttons[label]
    }

    private func tapCenter(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The "to clear" counter at zero. A plain substring match would also hit "7.0 MB to clear".
    private func emptyPile(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "0 MB ")).firstMatch
    }

    private func drag(
        _ app: XCUIApplication,
        from origin: CGVector = CGVector(dx: 0.5, dy: 0.5),
        to target: CGVector,
        hold: TimeInterval = 0.05
    ) {
        let start = app.coordinate(withNormalizedOffset: origin)
        start.press(forDuration: hold, thenDragTo: app.coordinate(withNormalizedOffset: target))
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        // The mock library, and the swipe demo counted as seen so it can't move the card.
        app.launchArguments = ["-mockLibrary", "YES", "-hasSeenSwipeHint", "YES"] + arguments
        app.launch()
        return app
    }
}
