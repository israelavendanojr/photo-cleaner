/// What pressing and holding a Live Photo does, apart from the view, so it can be tested (JUN-105).
///
/// A press plays the motion once it has loaded; a press that lands while it's still downloading waits
/// and plays when it arrives, if the finger is still down. Letting go stops it. The motion can also end
/// on its own while held; it doesn't start again until the next press. A failed load leaves the still.
struct LiveHold: Equatable {
    private(set) var isHolding = false
    private(set) var isLoaded = false
    private(set) var loadFailed = false
    private(set) var isPlaying = false

    /// A press waiting for the motion to download: the viewer says so.
    var isWaiting: Bool { isHolding && !isLoaded && !loadFailed }

    /// The finger went down. True if playback starts now.
    mutating func press() -> Bool {
        isHolding = true
        return play()
    }

    /// The finger lifted, or a drag or pinch took over.
    mutating func release() {
        isHolding = false
        isPlaying = false
    }

    /// The motion arrived (`true`) or couldn't be loaded. True if a press waiting on it starts playing now.
    mutating func loaded(_ succeeded: Bool) -> Bool {
        isLoaded = succeeded
        loadFailed = !succeeded
        return isHolding && play()
    }

    /// VoiceOver's "Play Live Photo", which can't hold: it plays once through. True if it starts.
    mutating func playOnce() -> Bool {
        play()
    }

    /// The motion reached its end by itself, or the player stopped.
    mutating func ended() {
        isPlaying = false
    }

    private mutating func play() -> Bool {
        guard isLoaded, !isPlaying else { return false }
        isPlaying = true
        return true
    }
}
