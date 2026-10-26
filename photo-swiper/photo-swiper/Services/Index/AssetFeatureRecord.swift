import Foundation
import SwiftData

/// One asset's cached features, keyed by `PHAsset.localIdentifier`.
///
/// Fields are flat scalars rather than a nested Codable so they stay queryable. `modifiedAt` and
/// `featureVersion` decide when a record is stale; see `IndexFreshness`.
@Model
final class AssetFeatureRecord {
    @Attribute(.unique) var localIdentifier: String

    // `AssetFeatures` metadata.
    var createdAt: Date
    var bytes: Int64
    var isVideo: Bool
    var duration: Double
    var isScreenshot: Bool
    var isFavorite: Bool
    var isInBurst: Bool
    var isBurstPick: Bool
    var hasAdjustments: Bool
    var burstID: String?
    var isUserBurstPick: Bool?

    // Image signals; nil when not analyzed.
    var sharpness: Double?
    var exposureMean: Double?
    var darkFraction: Double?
    var brightFraction: Double?
    var aesthetic: Double?
    var isUtility: Bool?
    /// Float32 vector bytes; see `FeaturePrint`. Only `FeatureIndex.featurePrints(for:)` reads it.
    @Attribute(.externalStorage) var featurePrint: Data?

    /// The asset's `modificationDate` when it was indexed. A different one means it was edited since.
    var modifiedAt: Date?
    var featureVersion: Int
    var indexedAt: Date

    init(_ entry: IndexEntry) {
        localIdentifier = entry.id
        createdAt = entry.features.createdAt
        bytes = entry.features.bytes
        isVideo = entry.features.isVideo
        duration = entry.features.duration
        isScreenshot = entry.features.isScreenshot
        isFavorite = entry.features.isFavorite
        isInBurst = entry.features.isInBurst
        isBurstPick = entry.features.isBurstPick
        hasAdjustments = entry.features.hasAdjustments
        modifiedAt = entry.modifiedAt
        featureVersion = entry.version
        indexedAt = entry.indexedAt
        update(from: entry)
    }

    func update(from entry: IndexEntry) {
        let features = entry.features
        createdAt = features.createdAt
        bytes = features.bytes
        isVideo = features.isVideo
        duration = features.duration
        isScreenshot = features.isScreenshot
        isFavorite = features.isFavorite
        isInBurst = features.isInBurst
        isBurstPick = features.isBurstPick
        hasAdjustments = features.hasAdjustments
        burstID = features.burstID
        isUserBurstPick = features.isUserBurstPick
        sharpness = features.sharpness
        exposureMean = features.exposure?.mean
        darkFraction = features.exposure?.darkFraction
        brightFraction = features.exposure?.brightFraction
        aesthetic = features.aesthetic
        isUtility = features.isUtility
        featurePrint = entry.featurePrint
        modifiedAt = entry.modifiedAt
        featureVersion = entry.version
        indexedAt = entry.indexedAt
    }

    var features: AssetFeatures {
        var exposure: ExposureStats?
        if let exposureMean, let darkFraction, let brightFraction {
            exposure = ExposureStats(mean: exposureMean, darkFraction: darkFraction, brightFraction: brightFraction)
        }
        return AssetFeatures(
            createdAt: createdAt, bytes: bytes, isVideo: isVideo, duration: duration, isScreenshot: isScreenshot,
            isFavorite: isFavorite, isInBurst: isInBurst, isBurstPick: isBurstPick, burstID: burstID,
            isUserBurstPick: isUserBurstPick, hasAdjustments: hasAdjustments,
            sharpness: sharpness, exposure: exposure, aesthetic: aesthetic, isUtility: isUtility
        )
    }

    var stamp: IndexStamp { IndexStamp(modifiedAt: modifiedAt, version: featureVersion) }
}
