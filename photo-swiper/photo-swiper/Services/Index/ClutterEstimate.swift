import Foundation

/// A rough count of what's left to clear, shown as "about" on the swipe wall and in reminders.
struct ClutterEstimate: Equatable, Sendable {
    /// Undecided items the ranker scores as likely clears, and their size.
    var likelyClearCount = 0
    var likelyClearBytes: Int64 = 0
    /// Undecided screenshots.
    var screenshotCount = 0
    /// Similar-shot sets still to review.
    var similarGroupCount = 0

    /// Days of free swipes it would take to get through the likely clears.
    func daysToFinish(swipesPerDay: Double) -> Double {
        swipesPerDay > 0 ? Double(likelyClearCount) / swipesPerDay : 0
    }
}

extension FeedRanker {
    /// Scores at or above this read as clutter: screenshots, big videos, bursts, blurry or accidental shots.
    /// An ordinary few-megabyte photo scores well under it.
    static let likelyClearThreshold = 1.0
}

extension FeatureIndexReading {
    /// Counts from cached features only, no feature prints and no PhotoKit, so it's cheap enough to
    /// run whenever the wall opens. Items not indexed yet aren't counted, hence "about".
    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date, ranker: FeedRanker = FeedRanker()) async -> ClutterEstimate {
        var estimate = ClutterEstimate()
        for (id, record) in await indexed() where !excluding.contains(id) {
            let features = record.features
            if features.isScreenshot { estimate.screenshotCount += 1 }
            guard !features.isFavorite, ranker.score(features, now: now).total >= FeedRanker.likelyClearThreshold else { continue }
            estimate.likelyClearCount += 1
            estimate.likelyClearBytes += features.bytes
        }
        return estimate
    }
}
