import Foundation

/// Scores how worth reviewing an item is. Higher comes first.
///
/// Hand-tuned weights for now; a model learned from swipes replaces `Weights` later. Pure and
/// deterministic, so tests pin its behavior and the debug badge can show exactly why an item ranked
/// where it did. Scores are relative: only their order matters.
struct FeedRanker: Sendable {
    struct Weights: Sendable, Equatable {
        /// Per tenfold size above 1 MB: 2 MB ≈ 0.3, 50 MB ≈ 1.7, 2 GB ≈ 3.3.
        var size = 1.0
        /// Per minute of video, up to `videoMinutesCap`.
        var videoMinute = 0.2
        var videoMinutesCap = 5.0
        /// Flat boost for any screenshot; they're rarely kept.
        var screenshot = 1.0
        /// Per 30 days of screenshot age, up to `screenshotMonthsCap`. Old screenshots are almost always done with.
        var screenshotMonth = 0.5
        var screenshotMonthsCap = 3.0
        /// Per year of age, up to `ageYearsCap`. Old clutter is a surer call than last week's.
        var ageYear = 0.1
        var ageYearsCap = 5.0
        /// A burst frame neither the camera nor the user picked.
        var extraBurstFrame = 1.0
        /// Someone spent time editing it.
        var edited = -1.5
        var favorite = -2.0
        /// A pocket shot, blown-out frame, or soft junk. See `ImageFlags.isAccidental`.
        var accidental = 2.0
        /// Reads as blurry. See `ImageFlags.isBlurry`.
        var blurry = 1.0
        /// A receipt, document, or code: useful once, rarely worth keeping.
        var utility = 0.8
        /// Per point of aesthetics score below zero, so -1 adds the full weight.
        var lowAesthetic = 1.0
        /// Aesthetics scores above `highAestheticFrom` sink, reaching this at a score of 1.
        var highAesthetic = -0.5
        var highAestheticFrom = 0.5
    }

    /// One reason for a score, e.g. "size" +1.70.
    struct Part: Hashable, Sendable {
        let name: String
        let value: Double
    }

    struct Breakdown: Hashable, Sendable {
        let parts: [Part]
        var total: Double { parts.reduce(0) { $0 + $1.value } }
    }

    var weights = Weights()

    func score(_ features: AssetFeatures, now: Date) -> Breakdown {
        let w = weights
        let megabytes = Double(max(features.bytes, 1)) / 1_000_000
        let ageDays = max(0, now.timeIntervalSince(features.createdAt)) / 86_400

        var parts = [Part(name: "size", value: w.size * min(max(log10(megabytes), -1), 4))]
        if features.isVideo {
            parts.append(Part(name: "video", value: w.videoMinute * min(features.duration / 60, w.videoMinutesCap)))
        }
        if features.isScreenshot {
            parts.append(Part(name: "screenshot", value: w.screenshot))
            parts.append(Part(name: "shot age", value: w.screenshotMonth * min(ageDays / 30, w.screenshotMonthsCap)))
        }
        parts.append(Part(name: "age", value: w.ageYear * min(ageDays / 365, w.ageYearsCap)))
        if features.isInBurst, !features.isBurstPick {
            parts.append(Part(name: "burst", value: w.extraBurstFrame))
        }
        if features.hasAdjustments {
            parts.append(Part(name: "edited", value: w.edited))
        }
        if features.isFavorite {
            parts.append(Part(name: "favorite", value: w.favorite))
        }
        // Image signals only exist once the index has analyzed the item. Without them the score is unchanged.
        if ImageFlags.isAccidental(features) {
            parts.append(Part(name: "accidental", value: w.accidental))
        } else if ImageFlags.isBlurry(features) {
            parts.append(Part(name: "blurry", value: w.blurry))
        }
        if features.isUtility == true {
            parts.append(Part(name: "utility", value: w.utility))
        }
        if let aesthetic = features.aesthetic {
            if aesthetic < 0 {
                parts.append(Part(name: "low aesthetic", value: w.lowAesthetic * min(-aesthetic, 1)))
            } else if aesthetic > w.highAestheticFrom {
                let above = (min(aesthetic, 1) - w.highAestheticFrom) / (1 - w.highAestheticFrom)
                parts.append(Part(name: "high aesthetic", value: w.highAesthetic * above))
            }
        }
        return Breakdown(parts: parts.filter { $0.value != 0 })
    }
}
