import Testing
@testable import photo_swiper

/// Pressing and holding a Live Photo while its motion loads, plays and ends (JUN-105).
/// Each step's result is read before it's checked: the hold mutates.
struct LiveHoldTests {
    @Test func aPressAfterTheMotionLoadedPlaysAtOnce() {
        var hold = LiveHold()
        let playsOnLoad = hold.loaded(true)
        #expect(!playsOnLoad, "Nothing plays without a press")
        let plays = hold.press()
        #expect(plays)
        #expect(hold.isPlaying && !hold.isWaiting)
        hold.release()
        #expect(!hold.isPlaying)
    }

    @Test func aPressBeforeTheMotionLoadedWaitsThenPlays() {
        var hold = LiveHold()
        let playsAtOnce = hold.press()
        #expect(!playsAtOnce)
        #expect(hold.isWaiting, "The viewer says it's loading")
        let playsOnLoad = hold.loaded(true)
        #expect(playsOnLoad, "Still held when it arrives: it plays")
        #expect(hold.isPlaying && !hold.isWaiting)
    }

    @Test func aPressLetGoBeforeTheMotionLoadedNeverPlays() {
        var hold = LiveHold()
        _ = hold.press()
        hold.release()
        let playsOnLoad = hold.loaded(true)
        #expect(!playsOnLoad)
        #expect(!hold.isPlaying && !hold.isWaiting)
    }

    @Test func motionThatEndsWhileHeldDoesNotStartAgainUntilTheNextPress() {
        var hold = LiveHold()
        _ = hold.loaded(true)
        _ = hold.press()
        hold.ended()
        #expect(!hold.isPlaying)
        #expect(hold.isHolding, "Still held: the still shows")
        hold.release()
        let playsAgain = hold.press()
        #expect(playsAgain, "A new press plays again")
    }

    @Test func aFailedLoadStopsWaitingAndNeverPlays() {
        var hold = LiveHold()
        _ = hold.press()
        let playsOnLoad = hold.loaded(false)
        #expect(!playsOnLoad)
        #expect(!hold.isWaiting, "The loading pill goes away")
        hold.release()
        let plays = hold.press()
        #expect(!plays && !hold.isPlaying)
    }

    @Test func voiceOverPlaysOnceWithoutAHold() {
        var hold = LiveHold()
        let beforeLoad = hold.playOnce()
        #expect(!beforeLoad, "Not before it loads")
        _ = hold.loaded(true)
        let first = hold.playOnce()
        let second = hold.playOnce()
        #expect(first)
        #expect(!second, "Not twice at once")
        hold.ended()
        let afterEnd = hold.playOnce()
        #expect(afterEnd)
    }
}
