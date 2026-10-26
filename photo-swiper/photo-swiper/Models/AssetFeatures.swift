import Foundation

/// What the ranker knows about one item: metadata, plus image signals once the library index has
/// analyzed it.
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
    /// `PHAsset.burstIdentifier`: every frame of one burst shares it.
    var burstID: String?
    /// The user picked this frame in Photos, as opposed to the camera's automatic pick. Optional so
    /// items saved before it existed still decode; nil reads as false.
    var isUserBurstPick: Bool?
    /// Edited in Photos or another app.
    var hasAdjustments = false

    // Image signals. Nil means not analyzed: not indexed yet, a screenshot or video, or no local image.

    /// Laplacian variance of the sharpest tile, on a 0–255 grayscale. Higher is sharper.
    var sharpness: Double?
    var exposure: ExposureStats?
    /// Vision's overall aesthetics score, -1...1.
    var aesthetic: Double?
    /// Vision thinks it's a utility shot: a receipt, document, code, or similar.
    var isUtility: Bool?
}

/// How light or dark a frame is, from its luminance histogram.
struct ExposureStats: Hashable, Sendable, Codable {
    /// Mean luminance, 0...1.
    var mean: Double
    /// Share of pixels that are nearly black.
    var darkFraction: Double
    /// Share of pixels that are nearly white.
    var brightFraction: Double
}
