import Testing
@testable import photo_swiper

/// Press-and-hold 2x in the full-screen video: the boost goes back to the play state from
/// before it, and scrubbing, pausing, or stopping cancel it.
@MainActor
struct VideoBoostTests {
    @Test func holdWhilePlayingKeepsPlayingAtNormalSpeedOnRelease() {
        let playback = VideoPlayback()
        playback.play()

        playback.beginBoost()
        #expect(playback.isBoosted)
        #expect(playback.isPlaying)
        #expect(playback.player.defaultRate == VideoPlayback.boostRate)

        playback.endBoost()
        #expect(!playback.isBoosted)
        #expect(playback.isPlaying)
        #expect(playback.player.defaultRate == 1)
    }

    @Test func holdWhilePausedPlaysThenPausesAgainOnRelease() {
        let playback = VideoPlayback()
        #expect(!playback.isPlaying)

        playback.beginBoost()
        #expect(playback.isBoosted)
        #expect(playback.isPlaying, "Holding a paused video plays it at 2x")

        playback.endBoost()
        #expect(!playback.isBoosted)
        #expect(!playback.isPlaying, "Letting go pauses it again")
    }

    @Test func voiceOverNormalSpeedKeepsPlaying() {
        let playback = VideoPlayback()
        playback.beginBoost()

        playback.endBoost(restoring: false)
        #expect(!playback.isBoosted)
        #expect(playback.isPlaying)
    }

    @Test func scrubbingCancelsBoostAndRestoresPriorState() {
        let playback = VideoPlayback()
        playback.beginBoost()

        playback.beginScrubbing()
        #expect(!playback.isBoosted)
        playback.endScrubbing()
        #expect(!playback.isPlaying, "Was paused before the hold, so stays paused after scrubbing")
    }

    @Test func scrubbingWhileBoostedFromPlayingResumesAtNormalSpeed() {
        let playback = VideoPlayback()
        playback.play()
        playback.beginBoost()

        playback.beginScrubbing()
        playback.endScrubbing()
        #expect(!playback.isBoosted)
        #expect(playback.isPlaying)
        #expect(playback.player.defaultRate == 1)
    }

    @Test func pausingDropsBoost() {
        let playback = VideoPlayback()
        playback.beginBoost()

        playback.pause()
        #expect(!playback.isBoosted)
        playback.play()
        #expect(playback.player.defaultRate == 1, "The next play is at normal speed")

        // A late release after the pause changes nothing.
        playback.endBoost()
        #expect(playback.isPlaying)
    }

    @Test func beginningTwiceKeepsTheFirstPriorState() {
        let playback = VideoPlayback()
        playback.beginBoost()
        playback.beginBoost()

        playback.endBoost()
        #expect(!playback.isPlaying)
    }

    @Test func stopEndsBoost() {
        let playback = VideoPlayback()
        playback.beginBoost()
        playback.stop()
        #expect(!playback.isBoosted)
        #expect(!playback.isPlaying)
    }
}
