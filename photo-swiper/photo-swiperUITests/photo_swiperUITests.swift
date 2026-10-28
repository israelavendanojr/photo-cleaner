//
//  photo_swiperUITests.swift
//  photo-swiperUITests
//
//  Created by Israel Avendano Jr. on 10/7/26.
//

import XCTest

/// Drives the real swipe gesture and buttons against the mock deck. The deck has no position to
/// read, so tests follow the top card through the debug `feed.currentCard` marker instead.
final class photo_swiperUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Drags and taps use portrait coordinates; a simulator left rotated breaks them.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testSwipeLeftAddsToPileAndUndoRestores() throws {
        let app = launch()
        let first = topCard(app)
        XCTAssertTrue(emptyPile(app).exists)

        drag(app, to: CGVector(dx: 0.02, dy: 0.5))

        XCTAssertTrue(waitForTopCard(app, not: first))
        XCTAssertFalse(emptyPile(app).exists, "Delete should add to the pile")

        app.buttons["Undo"].tap()

        XCTAssertTrue(waitForTopCard(app, is: first))
        XCTAssertTrue(emptyPile(app).waitForExistence(timeout: 3))
    }

    @MainActor
    func testOnboardingLeadsToFeed() throws {
        let app = launch("-startAt", "onboarding")
        XCTAssertTrue(element(app, containing: "Lighten your library.").waitForExistence(timeout: 5))
        attachScreenshot(app, "welcome")

        app.buttons["onboarding.welcome.continue"].tap()
        let allow = app.buttons["onboarding.access.continue"]
        XCTAssertTrue(allow.waitForExistence(timeout: 3))
        XCTAssertEqual(allow.label, "Continue", "App Review rejects pre-permission buttons that say Allow")
        XCTAssertTrue(element(app, containing: "One permission").exists)
        sleep(1)
        attachScreenshot(app, "photo access")

        allow.tap()
        XCTAssertTrue(waitForTopCard(app, not: "none", timeout: 8), "Continuing opens the feed")
        XCTAssertFalse(allow.exists)
    }

    @MainActor
    func testShortDragSnapsBack() throws {
        let app = launch()
        let first = topCard(app)

        drag(app, to: CGVector(dx: 0.4, dy: 0.5), hold: 0.4)

        sleep(1)
        XCTAssertEqual(cardMarker(app).label, first, "A short drag must not commit")
    }

    @MainActor
    func testSwipeUpIsLaterAndRightIsKeep() throws {
        let app = launch()
        let first = topCard(app)

        drag(app, to: CGVector(dx: 0.5, dy: 0.1))
        XCTAssertTrue(waitForTopCard(app, not: first))
        let second = cardMarker(app).label

        drag(app, to: CGVector(dx: 0.98, dy: 0.5))
        XCTAssertTrue(waitForTopCard(app, not: second))

        XCTAssertTrue(emptyPile(app).exists, "Later and Keep never add to the pile")
    }

    @MainActor
    func testSimilarToggleThenDeleteButton() throws {
        let app = launch("-startAt", "similar")
        // The corner mark is its own button; the rest of the thumbnail opens the review.
        let shot = app.buttons["Shot 2"]
        XCTAssertTrue(shot.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open shot 2"].exists)
        XCTAssertEqual(shot.value as? String, "Marked to clear")
        let similar = topCard(app)

        tapCenter(shot)
        XCTAssertEqual(shot.value as? String, "Keeping")
        XCTAssertFalse(element(app, containing: "of 6").exists, "Toggling doesn't open the review")

        app.buttons["Delete"].tap()

        XCTAssertTrue(waitForTopCard(app, not: similar))
        XCTAssertFalse(emptyPile(app).exists)
    }

    @MainActor
    func testSimilarHeroOpensReviewOnTheBestPick() throws {
        let app = launch("-startAt", "similar")
        let hero = similarHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        attachScreenshot(app, "similar card")

        tapCenter(hero)

        XCTAssertTrue(element(app, containing: "Similar shots").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, containing: "1 of 6").exists)
        XCTAssertTrue(element(app, containing: "Photo, Best pick. Sharpest of the set").exists, "The best pick shows its chip")
        attachScreenshot(app, "similar review on best pick")
    }

    @MainActor
    func testSimilarThumbnailOpensReviewOnThatShot() throws {
        let app = launch("-startAt", "similar")
        let open = app.buttons["Open shot 3"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))

        tapCenter(open)

        XCTAssertTrue(element(app, containing: "1 of 6").waitForExistence(timeout: 3))
        sleep(1)
        XCTAssertFalse(element(app, containing: "Photo, Best pick").exists, "It opens on shot 3, not the best pick")
        // Shots 3 to 6, then it wraps to the best pick and shot 2.
        for _ in 0..<4 { tapAndWait(onScreen(app, "Keep")) }
        XCTAssertTrue(element(app, containing: "5 of 6").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, containing: "Photo, Best pick").exists, "It wraps around to the best pick")
    }

    @MainActor
    func testFinishingSimilarReviewClearsOnlyDeletedShots() throws {
        let app = launch("-startAt", "similar")
        let position = topCard(app)
        let hero = similarHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        tapCenter(hero)
        XCTAssertTrue(element(app, containing: "1 of 6").waitForExistence(timeout: 3))

        tapAndWait(onScreen(app, "Keep"))
        tapAndWait(onScreen(app, "Delete"))
        XCTAssertTrue(element(app, containing: "3 of 6").waitForExistence(timeout: 3))
        for _ in 0..<4 { tapAndWait(onScreen(app, "Keep")) }

        XCTAssertTrue(element(app, containing: "of 6").waitForNonExistence(timeout: 5), "The review closes")
        XCTAssertTrue(waitForTopCard(app, not: position), "The similar card leaves the feed")
        XCTAssertTrue(element(app, containing: "MB to clear").exists)
        XCTAssertFalse(emptyPile(app).exists, "The deleted shot joins the pile")
        attachScreenshot(app, "after similar review")

        tapCenter(onScreen(app, "Undo"))
        XCTAssertTrue(waitForTopCard(app, is: position))
        XCTAssertTrue(emptyPile(app).waitForExistence(timeout: 3), "Undo restores the whole set")
    }

    @MainActor
    func testClosingSimilarReviewEarlyKeepsADraft() throws {
        let app = launch("-startAt", "similar")
        let position = topCard(app)
        let hero = similarHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        tapCenter(hero)
        XCTAssertTrue(element(app, containing: "1 of 6").waitForExistence(timeout: 3))

        tapAndWait(onScreen(app, "Delete"))
        tapAndWait(onScreen(app, "Keep"))
        XCTAssertTrue(element(app, containing: "3 of 6").waitForExistence(timeout: 3))
        tapCenter(onScreen(app, "Close"))

        XCTAssertTrue(element(app, containing: "of 6").waitForNonExistence(timeout: 3), "The review closes")
        XCTAssertTrue(waitForTopCard(app, is: position), "Closing early decides nothing")
        XCTAssertTrue(emptyPile(app).exists)
        XCTAssertEqual(hero.value as? String, "Marked to clear", "The card shows the draft's delete")
        XCTAssertEqual(app.buttons["Shot 2"].value as? String, "Keeping", "The card shows the draft's keep")
        XCTAssertEqual(app.buttons["Shot 3"].value as? String, "Marked to clear", "Unreached shots keep their mark")
        attachScreenshot(app, "card with draft")

        tapCenter(hero)
        XCTAssertTrue(element(app, containing: "3 of 6").waitForExistence(timeout: 3), "Reopening resumes")
    }

    @MainActor
    func testSimilarReviewPhotoOpensFullScreen() throws {
        let app = launch("-startAt", "similar")
        let hero = similarHero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        tapCenter(hero)
        XCTAssertTrue(element(app, containing: "1 of 6").waitForExistence(timeout: 3))
        sleep(1)

        let preview = app.descendants(matching: .any)["photoPreview"]
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 3), "Shots open full screen like the feed")
        attachScreenshot(app, "similar shot full screen")
        swipeDown(app)
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "Swiping down closes the preview")
        XCTAssertTrue(element(app, containing: "1 of 6").exists, "Looking doesn't move the review")
        sleep(1)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        drag(app, to: CGVector(dx: 0.02, dy: 0.5))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "A decision closes the preview")
        XCTAssertTrue(element(app, containing: "2 of 6").waitForExistence(timeout: 3), "A full-screen swipe decides the shot")
        // The feed's counter is still at zero under the review; the review's own one counts the delete.
        let reviewCounter = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ENDSWITH %@ AND NOT label BEGINSWITH %@", "MB to clear", "0 MB "))
        XCTAssertTrue(reviewCounter.firstMatch.waitForExistence(timeout: 2), "Delete in full screen counts toward clearing")
    }

    @MainActor
    func testBatchOneByOneClearsOnlyDeletedItems() throws {
        let app = launch("-startAt", "batch")
        let position = topCard(app)
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

        XCTAssertTrue(element(app, containing: "of 14").waitForNonExistence(timeout: 5), "The review closes")
        XCTAssertTrue(waitForTopCard(app, not: position), "The batch card is decided")
        XCTAssertFalse(emptyPile(app).exists, "Deleted items join the pile")
        attachScreenshot(app, "back in feed")

        tapCenter(onScreen(app, "Undo"))
        XCTAssertTrue(waitForTopCard(app, is: position))
        XCTAssertTrue(emptyPile(app).waitForExistence(timeout: 3), "Undo restores the whole batch")
    }

    @MainActor
    func testClosingBatchReviewEarlyChangesNothing() throws {
        let app = launch("-startAt", "batch")
        let position = topCard(app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(element(app, containing: "1 of 14").waitForExistence(timeout: 3))
        tapAndWait(onScreen(app, "Delete"))
        XCTAssertTrue(element(app, containing: "2 of 14").waitForExistence(timeout: 3))
        tapCenter(onScreen(app, "Close"))

        XCTAssertTrue(element(app, containing: "of 14").waitForNonExistence(timeout: 3), "The review closes")
        XCTAssertTrue(waitForTopCard(app, is: position))
        XCTAssertTrue(emptyPile(app).exists)
    }

    @MainActor
    func testBatchReviewPhotoOpensFullScreen() throws {
        let app = launch("-startAt", "batch")
        _ = topCard(app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(element(app, containing: "1 of 14").waitForExistence(timeout: 3))
        sleep(1)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let preview = app.descendants(matching: .any)["photoPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3), "Batch items open full screen like the feed")
        attachScreenshot(app, "batch item full screen")

        swipeDown(app)
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "Swiping down closes the preview")
        XCTAssertTrue(element(app, containing: "1 of 14").exists, "Looking doesn't move the review")
        XCTAssertTrue(emptyPile(app).exists, "Looking decides nothing")
    }

    @MainActor
    func testVideoPreviewPlaysScrubsAndClosesWithoutDeciding() throws {
        let app = launch("-startAt", "video")
        XCTAssertTrue(element(app, containing: "Video ·").waitForExistence(timeout: 5))
        let position = topCard(app)

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
        XCTAssertTrue(waitForTopCard(app, is: position), "Watching doesn't move the feed")
        XCTAssertTrue(emptyPile(app).exists, "Watching decides nothing")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3))
        swipeDown(app)
        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 3), "Swiping down closes the preview")
        XCTAssertTrue(waitForTopCard(app, is: position), "Swiping out doesn't move the feed")
        XCTAssertTrue(emptyPile(app).exists, "Swiping out decides nothing")
    }

    @MainActor
    func testPhotoPreviewOpensZoomsAndClosesWithoutDeciding() throws {
        let app = launch()
        let position = topCard(app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let preview = app.descendants(matching: .any)["photoPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        attachScreenshot(app, "fit")

        preview.doubleTap()
        sleep(1)
        attachScreenshot(app, "zoomed")

        tapCenter(onScreen(app, "Close"))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "The preview closes")
        XCTAssertTrue(waitForTopCard(app, is: position), "Looking doesn't move the feed")
        XCTAssertTrue(emptyPile(app).exists, "Looking decides nothing")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        swipeDown(app)
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "Swiping down closes the preview")
        XCTAssertTrue(waitForTopCard(app, is: position), "Swiping out doesn't move the feed")
        XCTAssertTrue(emptyPile(app).exists, "Swiping out decides nothing")
    }

    @MainActor
    func testPhotoPreviewSwipesDecide() throws {
        let app = launch()
        let position = topCard(app)
        let preview = app.descendants(matching: .any)["photoPreview"]

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        drag(app, to: CGVector(dx: 0.02, dy: 0.5))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "A decision closes the preview")
        XCTAssertTrue(waitForTopCard(app, not: position), "The card leaves the deck")
        XCTAssertFalse(emptyPile(app).exists, "Delete in full screen adds to the pile")

        app.buttons["Undo"].tap()
        XCTAssertTrue(waitForTopCard(app, is: position))
        XCTAssertTrue(emptyPile(app).waitForExistence(timeout: 3), "Undo restores a full-screen decision")
        sleep(1)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        drag(app, to: CGVector(dx: 0.5, dy: 0.1))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForTopCard(app, not: position), "Swiping up is Later, not close")
        XCTAssertTrue(emptyPile(app).exists, "Later never adds to the pile")
    }

    /// A slow drag the way a finger does it: a short one springs back and decides nothing, a
    /// long one held past the threshold still decides on release.
    @MainActor
    func testPhotoPreviewSlowSwipeTracksFinger() throws {
        let app = launch()
        let position = topCard(app)
        let preview = app.descendants(matching: .any)["photoPreview"]

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        slowDrag(app, to: CGVector(dx: 0.4, dy: 0.5))
        sleep(1)
        XCTAssertTrue(preview.exists, "A short drag springs back")
        XCTAssertTrue(waitForTopCard(app, is: position))

        slowDrag(app, to: CGVector(dx: 0.12, dy: 0.5))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3), "Held past the threshold, it decides")
        XCTAssertFalse(emptyPile(app).exists, "Delete in full screen adds to the pile")
    }

    @MainActor
    func testVideoPreviewSwipeRightKeeps() throws {
        let app = launch("-startAt", "video")
        XCTAssertTrue(element(app, containing: "Video ·").waitForExistence(timeout: 5))
        let position = topCard(app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let scrubber = app.descendants(matching: .any)["videoScrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3))
        slowDrag(app, to: CGVector(dx: 0.88, dy: 0.5))
        XCTAssertTrue(scrubber.waitForNonExistence(timeout: 3), "A decision closes the preview")
        XCTAssertTrue(waitForTopCard(app, not: position), "The card leaves the deck")
        XCTAssertTrue(emptyPile(app).exists, "Keep never adds to the pile")
    }

    @MainActor
    func testPendingPileDeletesByDefaultAndKeepsUnmarked() throws {
        let app = launch()
        for _ in 1...3 {
            let card = topCard(app)
            drag(app, to: CGVector(dx: 0.02, dy: 0.5))
            XCTAssertTrue(waitForTopCard(app, not: card))
        }
        let fourth = cardMarker(app).label

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

        let freed = element(app, containing: "they stay in Recently Deleted for 30 days")
        XCTAssertTrue(freed.waitForExistence(timeout: 3), "The pile says what was freed")
        XCTAssertTrue(freed.label.hasPrefix("Freed "))
        attachScreenshot(app, "freed")
        XCTAssertTrue(bin.waitForNonExistence(timeout: 4), "Then it closes by itself")

        // Mocks start locked, so the unlock is offered once the pile has closed.
        let notNow = app.buttons["paywall.notNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 4))
        notNow.tap()
        XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))

        XCTAssertTrue(emptyPile(app).waitForExistence(timeout: 3))
        XCTAssertEqual(cardMarker(app).label, fourth, "The pile doesn't move the feed")
    }

    @MainActor
    func testFreeDeleteOffersTheUnlockAfterThePileCloses() throws {
        let app = launch("-startAt", "pending", "-showPile", "YES", "-unlocked", "NO")
        let limit = app.descendants(matching: .any)["pile.limit"]
        XCTAssertTrue(limit.waitForExistence(timeout: 5), "Free users see how full the pile is")
        XCTAssertTrue(limit.label.contains("of 50 photos"))
        deleteAllInPile(app)

        let unlock = app.buttons["paywall.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "The unlock is offered after the delete")
        let title = app.staticTexts["unlock.title"]
        XCTAssertTrue(title.label.hasPrefix("Freed "), "The headline says what was freed")
        XCTAssertTrue(element(app, containing: "Unlock to keep going without limits").exists)
        sleep(1)
        attachScreenshot(app, "unlock after delete")

        app.buttons["paywall.notNow"].tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 3))
        XCTAssertTrue(emptyPile(app).waitForExistence(timeout: 3))
    }

    @MainActor
    func testUnlockedDeleteOffersNothing() throws {
        let app = launch("-startAt", "pending", "-showPile", "YES", "-unlocked", "YES")
        XCTAssertTrue(app.buttons["binButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["pile.limit"].exists, "No limit once unlocked")
        deleteAllInPile(app)

        XCTAssertTrue(emptyPile(app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["paywall.unlock"].waitForExistence(timeout: 2))
    }

    // MARK: The endless deck

    @MainActor
    func testSwipingPastTheFirstPageKeepsGoing() throws {
        let app = launch("-unlocked", "YES")
        let first = topCard(app)
        XCTAssertTrue(first.contains("s1-"), "The deck opens on the first page")

        // Past the first page's last card, with time for each fly-out.
        for _ in 0..<22 { tapAndWait(onScreen(app, "Keep")) }

        XCTAssertTrue(waitForTopCard(app, containing: "s2-"), "The next page carries straight on")
        XCTAssertFalse(element(app, containing: "All caught up").exists)
        XCTAssertTrue(app.buttons["Undo"].isEnabled, "Still the same feed: the last swipe can be undone")
        attachScreenshot(app, "second page")
    }

    @MainActor
    func testRelaunchResumesOnTheSameCard() throws {
        var app = launch("-mockProgress", "YES", "-resetProgress", "YES")
        _ = topCard(app)
        for direction in [CGVector(dx: 0.02, dy: 0.5), CGVector(dx: 0.98, dy: 0.5), CGVector(dx: 0.02, dy: 0.5)] {
            let card = cardMarker(app).label
            drag(app, to: direction)
            XCTAssertTrue(waitForTopCard(app, not: card))
        }
        // Lets the last save land before quitting.
        sleep(1)
        let resumed = cardMarker(app).label
        let pile = element(app, containing: "to clear").label
        app.terminate()

        app = launch("-mockProgress", "YES")
        XCTAssertTrue(waitForTopCard(app, is: resumed, timeout: 8), "Relaunching lands on the card left off at")
        XCTAssertEqual(element(app, containing: "to clear").label, pile, "The pile comes back too")
    }

    // MARK: The swipe wall

    @MainActor
    func testOutOfSwipesRefusesThenNotNowKeepsTheDeck() throws {
        let app = launch("-swipesLeft", "1", "-unlocked", "NO")
        let keep = onScreen(app, "Keep")
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["feed.swipesLeft"].waitForExistence(timeout: 3), "Few left shows the pill")
        let first = topCard(app)
        tapAndWait(keep)
        XCTAssertTrue(waitForTopCard(app, not: first))
        let second = cardMarker(app).label

        tapCenter(onScreen(app, "Keep"))
        let unlock = app.buttons["paywall.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "The swipe is refused and the wall opens")
        XCTAssertTrue(element(app, containing: "Out of swipes").exists)
        XCTAssertTrue(element(app, containing: "+10 in").exists)
        XCTAssertTrue(element(app, containing: "Unlimited swipes").exists)
        XCTAssertEqual(unlock.label, "Unlock for $12.99, one-time purchase")
        sleep(1)
        attachScreenshot(app, "swipe wall")

        app.buttons["paywall.notNow"].tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 3))
        XCTAssertEqual(cardMarker(app).label, second, "Nothing was committed; the deck stays")

        tapCenter(onScreen(app, "Delete"))
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "The next swipe asks again")
    }

    @MainActor
    func testUnlockFromTheWallLetsTheCardThrough() throws {
        let app = launch("-startAt", "outOfSwipes", "-unlocked", "NO")
        let unlock = app.buttons["paywall.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        unlock.tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 8), "The sheet closes")
        let before = topCard(app)
        tapAndWait(onScreen(app, "Keep"))
        XCTAssertTrue(waitForTopCard(app, not: before), "The card goes straight through")
    }

    @MainActor
    func testFailedRestoreShowsInlineMessage() throws {
        let app = launch("-startAt", "outOfSwipes", "-unlocked", "NO", "-restoreFails", "YES")
        let restore = app.buttons["paywall.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.staticTexts["paywall.message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paywall.unlock"].exists, "Still on the wall, no alert")
        attachScreenshot(app, "restore failed")
    }

    @MainActor
    func testWallShowsTermsLink() throws {
        let app = launch("-startAt", "outOfSwipes", "-unlocked", "NO")
        XCTAssertTrue(app.buttons["paywall.unlock"].waitForExistence(timeout: 5))
        let terms = app.buttons["legal.terms"]
        XCTAssertTrue(terms.exists, "Terms sits under the unlock")
        XCTAssertEqual(terms.label, "Terms of use")
        XCTAssertFalse(app.buttons["legal.privacy"].exists, "No privacy link until its URL is set")
    }

    // MARK: Settings

    @MainActor
    func testGearOpensSettings() throws {
        let app = launch()
        openSettings(app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.version"].exists, "About shows the version")
        attachScreenshot(app, "settings")
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.title"].waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testSkipFavoritesMovedToSettings() throws {
        let app = launch()
        app.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["library.settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Skip favorites")).firstMatch.exists,
                       "No longer on the Library tab")

        openSettings(app)
        let toggle = app.switches["settings.skipFavorites"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1", "On by default")
        flip(toggle)
        XCTAssertTrue(waitForValue(toggle, "0"))

        app.buttons["settings.done"].tap()
        openSettings(app)
        XCTAssertEqual(app.switches["settings.skipFavorites"].value as? String, "0", "The choice sticks")
    }

    @MainActor
    func testSettingsRestoreRuns() throws {
        let app = launch("-unlocked", "NO")
        openSettings(app)
        XCTAssertTrue(app.buttons["settings.unlock"].exists, "Locked shows the unlock row")
        let restore = app.buttons["settings.restore"]
        XCTAssertTrue(restore.exists)
        restore.tap()
        XCTAssertTrue(waitForLabel(restore, containing: "Restoring", timeout: 2), "Shows progress")
        XCTAssertTrue(app.descendants(matching: .any)["settings.unlocked"].waitForExistence(timeout: 5),
                      "The debug store restores, and the row thanks the user")
        XCTAssertTrue(restore.label.contains("Purchase restored"), restore.label)
        XCTAssertFalse(app.buttons["settings.unlock"].exists)
    }

    @MainActor
    func testSettingsRestoreWithNothingToRestore() throws {
        let app = launch("-unlocked", "NO", "-restoreFails", "YES")
        openSettings(app)
        let restore = app.buttons["settings.restore"]
        restore.tap()
        XCTAssertTrue(waitForLabel(restore, containing: "Nothing to restore", timeout: 5))
        XCTAssertTrue(app.buttons["settings.unlock"].exists, "Still locked")
    }

    @MainActor
    func testLegalRowsAndStubsInDebug() throws {
        let app = launch()
        openSettings(app)
        XCTAssertTrue(app.buttons["settings.terms"].exists, "Terms is always set")
        for id in ["settings.privacy", "settings.support", "settings.rate"] {
            let row = app.descendants(matching: .any)[id]
            XCTAssertTrue(row.exists, "\(id) shows in debug builds")
            XCTAssertTrue(row.label.contains("Not set yet"), "\(id) reads \(row.label)")
            XCTAssertFalse(app.buttons[id].exists, "\(id) isn't tappable while unset")
        }
    }

    @MainActor
    func testDebugResetSwipes() throws {
        let app = launch("-swipesLeft", "0", "-unlocked", "NO")
        openSettings(app)
        let left = app.descendants(matching: .any)["settings.debug.swipesLeft"]
        scrollTo(left, in: app)
        XCTAssertEqual(left.label, "Swipes left, 0")
        app.buttons["settings.debug.resetSwipes"].tap()
        XCTAssertEqual(left.label, "Swipes left, 20", "Back to the cap")
        app.buttons["settings.debug.zeroSwipes"].tap()
        XCTAssertEqual(left.label, "Swipes left, 0")
    }

    // MARK: Helpers

    /// Library tab, then the gear.
    private func openSettings(_ app: XCUIApplication) {
        let library = app.buttons["Library"]
        if library.waitForExistence(timeout: 5), library.isHittable { library.tap() }
        let gear = app.buttons["library.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.title"].waitForExistence(timeout: 3), "Settings opens")
    }

    /// Taps a SwiftUI switch on its knob; a tap on the label doesn't always flip it.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
    }

    /// The debug marker naming the top card by id, "none" while the deck waits on more.
    private func similarHero(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["similar.hero"]
    }

    private func cardMarker(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["feed.currentCard"]
    }

    /// Waits for the feed, then names its top card.
    private func topCard(_ app: XCUIApplication) -> String {
        let marker = cardMarker(app)
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "The feed shows")
        XCTAssertTrue(waitForTopCard(app, not: "none", timeout: 5))
        return marker.label
    }

    private func waitForTopCard(_ app: XCUIApplication, is id: String, timeout: TimeInterval = 3) -> Bool {
        waitForMarker(app, NSPredicate(format: "label == %@", id), timeout: timeout)
    }

    private func waitForTopCard(_ app: XCUIApplication, not id: String, timeout: TimeInterval = 3) -> Bool {
        waitForMarker(app, NSPredicate(format: "exists == true AND label != %@", id), timeout: timeout)
    }

    private func waitForTopCard(_ app: XCUIApplication, containing text: String, timeout: TimeInterval = 5) -> Bool {
        waitForMarker(app, NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
    }

    private func waitForMarker(_ app: XCUIApplication, _ predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: cardMarker(app))
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The full-screen batch review leaves the feed's buttons in the tree underneath it.
    /// Prefer an enabled match (the feed's Undo is disabled behind the review); tapping its
    /// center skips the scroll-to-visible step that fails on covered elements.
    /// Deletes everything in the open pile and waits for it to close.
    private func deleteAllInPile(_ app: XCUIApplication) {
        let bin = app.buttons["binButton"]
        XCTAssertTrue(bin.waitForExistence(timeout: 5))
        XCTAssertTrue(bin.isHittable, "The Delete button is clear of the home indicator")
        bin.tap()
        let confirm = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element(app, containing: "they stay in Recently Deleted").waitForExistence(timeout: 5))
        XCTAssertTrue(bin.waitForNonExistence(timeout: 4))
    }

    private func onScreen(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        // A full-screen cover leaves the feed's buttons in the tree underneath, in no fixed order.
        return matches.last { $0.isEnabled && $0.isHittable } ?? matches.last { $0.isEnabled } ?? matches.last ?? app.buttons[label]
    }

    private func tapAndWait(_ button: XCUIElement) {
        tapCenter(button)
        // Let the fly-out finish before the next card accepts input.
        usleep(550_000)
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

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        // Always the mock library, so tests never hit the photo permission prompt. The swipe
        // hint's nudge would move the card under a drag, so it counts as already seen.
        app.launchArguments = ["-mockLibrary", "YES", "-hasSeenSwipeHint", "YES"] + arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The "to clear" counter at zero. A plain substring match would also hit "7.0 MB to clear".
    private func emptyPile(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "0 MB ")).firstMatch
    }

    private func drag(_ app: XCUIApplication, to target: CGVector, hold: TimeInterval = 0.05) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: hold, thenDragTo: app.coordinate(withNormalizedOffset: target))
    }

    /// Moves slowly and holds at the end before lifting, so every step of the drag registers.
    private func slowDrag(_ app: XCUIApplication, to target: CGVector) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: target), withVelocity: .slow, thenHoldForDuration: 1)
    }
}
