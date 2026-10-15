import Foundation

/// What the ranker knows about one item. Metadata only for now; image-analysis signals join later.
///
/// Stored on `LibraryItem`, so every saved decision keeps the features it was made on.
/// That's the training data a learned ranker needs later.
struct AssetFeatures: Hashable, Sendable, Codable {
    var createdAt: Date
    var bytes: Int64
    var isVideo = false
    /// Seconds; zero for photos.
    var duration: TimeInterval = 0
    var isScreenshot = false
    var isFavorite = false
    /// Part of a burst, whether or not it's the frame that represents it.
    var isInBurst = false
    /// The burst frame the camera or the user chose.
    var isBurstPick = false
    /// Edited in Photos or another app.
    var hasAdjustments = false
}
