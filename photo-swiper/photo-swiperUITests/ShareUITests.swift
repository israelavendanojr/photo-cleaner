import XCTest

/// The Share button on a video card (JUN-8): tapping it prepares the file, then opens iOS's share sheet,
/// and closing the sheet leaves the card where it was, undecided.
final class ShareUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testSharingAVideoOpensTheShareSheetAndDecidesNothing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mockLibrary", "YES", "-hasSeenSwipeHint", "YES", "-resetTunables", "YES", "-startAt", "video"]
        app.launch()
        let position = topCard(app)
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Video, ")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        attachScreenshot(app, "card")

        // The button is bottom-trailing on the card. VoiceOver reaches it as the card's "Share" action,
        // so it isn't an element of its own.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.89, dy: 0.92)).tap()
        attachScreenshot(app, "preparing")

        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "The share sheet opens once the file is ready")
        attachScreenshot(app, "sheet")
        // The sheet attaches late while it loads its targets; that mustn't be taken for a refusal, which
        // deletes the file under the open sheet and shows this toast.
        let refused = app.staticTexts["Couldn't open the share sheet. Try again."]
        XCTAssertFalse(refused.waitForExistence(timeout: 2), "An opened sheet isn't reported as refused")

        let close = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Close", "Close")).firstMatch
        if close.waitForExistence(timeout: 2) {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "The sheet closes")
        XCTAssertEqual(cardMarker(app).label, position, "Sharing doesn't move the deck")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "0 MB ")).firstMatch.exists,
                      "Nothing went to the pile")
    }

    // MARK: Helpers

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
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
