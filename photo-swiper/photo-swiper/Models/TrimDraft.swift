import Foundation

/// The trim handles in the full-screen video, against what's saved for the video.
///
/// What's saved is either the whole video (no pending trim) or a pending trim's range. Leaving the viewer
/// asks first only when the handles differ from it, so dragging a pending trim's handles back to the ends
/// is a change too: saving that removes the trim (`result` is nil).
struct TrimDraft: Equatable {
    /// Shorter clips aren't worth trimming; they get a plain seek bar.
    static let minimumVideoLength: TimeInterval = 5
    /// The handles never come closer than this.
    static let minimumSelection: TimeInterval = 1
    /// Handles this close to an end count as at the end, and selections this close count as the same.
    static let tolerance: TimeInterval = 0.05

    let duration: TimeInterval
    /// The pending trim's range, or nil for the whole video.
    let saved: TrimRange?
    /// Where the handles are.
    private(set) var range: TrimRange

    /// `saved` is clamped to `duration`, which can differ a little from the length it was saved against.
    init(duration: TimeInterval, saved: TrimRange? = nil) {
        self.duration = max(duration, 0)
        let saved = saved.map { Self.clamped($0, duration: max(duration, 0)) }
        self.saved = saved.flatMap { Self.isFull($0, duration: max(duration, 0)) ? nil : $0 }
        range = self.saved ?? TrimRange(start: 0, end: max(duration, 0))
    }

    /// Long enough to trim. Slow-motion and Cinematic videos are left out by the caller.
    static func canTrim(duration: TimeInterval) -> Bool { duration >= minimumVideoLength }

    /// The handles are off the ends: the selection plays on a loop and the summary shows.
    var isTrimmed: Bool { !Self.isFull(range, duration: duration) }

    var hasUnsavedChanges: Bool {
        switch (isTrimmed ? range : nil, saved) {
        case (nil, nil): false
        case let (current?, saved?): !Self.same(current, saved)
        default: true
        }
    }

    /// What saving gives: the trim to queue, or nil when the handles are at the ends, which keeps the
    /// whole video and removes any pending trim.
    var result: PendingTrim? {
        isTrimmed ? PendingTrim(range: range, originalDuration: duration) : nil
    }

    /// Moves the start handle, never past the end handle less `minimumSelection`.
    mutating func setStart(_ seconds: TimeInterval) {
        range.start = min(max(seconds, 0), max(range.end - Self.minimumSelection, 0))
    }

    /// Moves the end handle, never before the start handle plus `minimumSelection`.
    mutating func setEnd(_ seconds: TimeInterval) {
        range.end = max(min(seconds, duration), min(range.start + Self.minimumSelection, duration))
    }

    /// Back to what's saved.
    mutating func reset() {
        range = saved ?? TrimRange(start: 0, end: duration)
    }

    private static func clamped(_ range: TrimRange, duration: TimeInterval) -> TrimRange {
        let start = min(max(range.start, 0), duration)
        return TrimRange(start: start, end: min(max(range.end, start), duration))
    }

    private static func isFull(_ range: TrimRange, duration: TimeInterval) -> Bool {
        range.start <= tolerance && range.end >= duration - tolerance
    }

    private static func same(_ a: TrimRange, _ b: TrimRange) -> Bool {
        abs(a.start - b.start) <= tolerance && abs(a.end - b.end) <= tolerance
    }
}
