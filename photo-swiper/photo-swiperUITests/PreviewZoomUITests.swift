import XCTest

/// Pinch zoom in the full-screen previews: zooming never decides, and while zoomed one finger
/// pans instead of swiping.
final class PreviewZoomUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testPinchedPhotoPansInsteadOfDeciding() throws {
        let app = launch()
        let position = topCard(app)
        let preview = app.descendants(matching: .any)["photoPreview"]

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        app.pinch(withScale: 3, velocity: 2)
        sleep(1)
        attachScreenshot(app, "pinched")
        XCTAssertTrue(preview.exists, "Pinching doesn't close the preview")

        drag(app, to: CGVector(dx: 0.02, dy: 0.5))
        sleep(1)
        attachScreenshot(app, "panned")
        XCTAssertTrue(preview.exists, "While zoomed, a swipe pans instead of deciding")

        // Back to fit, then a swipe closes again.
        app.doubleTap()
        sleep(1)
        swipeDown(app)
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "At rest, swiping down closes")
        XCTAssertTrue(waitForTopCard(app, is: position), "Zooming doesn't move the feed")
        XCTAssertTrue(emptyPile(app).exists, "Zooming decides nothing")
    }

    @MainActor
    func testPinchedVideoKeepsPlayingAndPansInsteadOfDeciding() throws {
        let app = launch("-startAt", "video")
        XCTAssertTrue(element(app, containing: "Video ·").waitForExistence(timeout: 5))
        let position = topCard(app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let scrubber = app.descendants(matching: .any)["videoScrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3))
        XCTAssertTrue(onScreen(app, "Pause").waitForExistence(timeout: 5), "Playback starts on open")
        // The mock clip is short: back to the start so it's still playing after the pinch.
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)))
        XCTAssertTrue(onScreen(app, "Pause").waitForExistence(timeout: 2), "Scrubbing resumes playback")
        let startedAt = scrubber.value as? String

        app.pinch(withScale: 3, velocity: 2)
        attachScreenshot(app, "pinched")
        XCTAssertTrue(scrubber.exists, "Pinching doesn't close the preview")
        // A slow simulated pinch can outlast the clip, so check the clock moved, not the button.
        XCTAssertNotEqual(scrubber.value as? String, startedAt, "Pinching doesn't stop playback")

        drag(app, to: CGVector(dx: 0.88, dy: 0.45))
        sleep(1)
        XCTAssertTrue(scrubber.exists, "While zoomed, a swipe pans instead of deciding")

        // The controls stay on top and working while zoomed.
        let shown = onScreen(app, "Play").exists ? onScreen(app, "Play") : onScreen(app, "Pause")
        let playPause = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: shown.frame.midX, dy: shown.frame.midY))
        if !onScreen(app, "Play").exists { playPause.tap() }
        XCTAssertTrue(onScreen(app, "Play").waitForExistence(timeout: 2), "Pause works while zoomed")
        playPause.tap()
        attachScreenshot(app, "play tapped while zoomed")
        XCTAssertTrue(onScreen(app, "Pause").waitForExistence(timeout: 2), "Play works while zoomed")
        playPause.tap()
        XCTAssertTrue(onScreen(app, "Play").waitForExistence(timeout: 2))
        let before = scrubber.value as? String
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertNotEqual(scrubber.value as? String, before, "The timeline scrubs while zoomed")

        app.doubleTap()
        sleep(1)
        swipeDown(app)
        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 3), "At rest, swiping down closes")
        XCTAssertTrue(waitForTopCard(app, is: position), "Zooming doesn't move the feed")
        XCTAssertTrue(emptyPile(app).exists, "Zooming decides nothing")
    }

    // MARK: Helpers

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockLibrary", "YES", "-hasSeenSwipeHint", "YES"] + arguments
        app.launch()
        return app
    }

    private func cardMarker(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["feed.currentCard"]
    }

    private func topCard(_ app: XCUIApplication) -> String {
        let marker = cardMarker(app)
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "The feed shows")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label != %@", "none"), object: marker)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 5), .completed)
        return marker.label
    }

    private func waitForTopCard(_ app: XCUIApplication, is id: String, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", id), object: cardMarker(app))
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The cover leaves the feed's buttons in the tree underneath; prefer the one on top.
    private func onScreen(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.last { $0.isEnabled && $0.isHittable } ?? matches.last { $0.isEnabled } ?? matches.last ?? app.buttons[label]
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func emptyPile(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "0 MB ")).firstMatch
    }

    private func drag(_ app: XCUIApplication, to target: CGVector) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: target))
    }

    /// Through the upper part of the screen, clear of the video timeline.
    private func swipeDown(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
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
