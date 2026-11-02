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

    // Exact-duplicate signals. Optional so items saved before they existed still decode.

    /// `PHAsset.pixelWidth` and `pixelHeight`, from metadata. Nil for mock items and older records.
    var pixelWidth: Int?
    var pixelHeight: Int?
    /// 64-bit difference hash of the upright image; see `DHash`. Nil when not hashed yet or no local image.
    var dHash: UInt64?

    /// Width over height, or nil without both dimensions.
    var aspectRatio: Double? {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else { return nil }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    var pixelCount: Int { (pixelWidth ?? 0) * (pixelHeight ?? 0) }
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
