import Foundation
import Photos

/// `PHAsset` → `LibraryItem` and `AssetFeatures`. Review flags come from `ImageFlags`.
enum AssetMapper {
    static func item(for asset: PHAsset, features: AssetFeatures, location: String?) -> LibraryItem {
        LibraryItem(
            id: asset.localIdentifier,
            kind: features.isVideo ? .video(duration: features.duration) : .photo,
            date: features.createdAt,
            location: location,
            bytes: features.bytes,
            flags: (features.isScreenshot ? [.screenshot] : []) + ImageFlags.classify(features),
            isFavorite: features.isFavorite,
            image: .photoKit(localIdentifier: asset.localIdentifier),
            features: features
        )
    }

    /// Metadata only: no pixels are loaded and nothing is downloaded from iCloud.
    static func features(for asset: PHAsset) -> AssetFeatures {
        let resources = PHAssetResource.assetResources(for: asset)
        let isVideo = asset.mediaType == .video
        return AssetFeatures(
            createdAt: asset.creationDate ?? asset.modificationDate ?? .distantPast,
            bytes: FileSizeReader.bytes(for: asset, resources: resources),
            isVideo: isVideo,
            duration: isVideo ? asset.duration : 0,
            isScreenshot: isScreenshot(asset),
            isFavorite: asset.isFavorite,
            isInBurst: asset.burstIdentifier != nil,
            isBurstPick: asset.representsBurst
                || !asset.burstSelectionTypes.isDisjoint(with: [.autoPick, .userPick]),
            burstID: asset.burstIdentifier,
            isUserBurstPick: asset.burstSelectionTypes.contains(.userPick),
            // An edit leaves a rendered copy and the adjustment recipe next to the original.
            hasAdjustments: resources.contains { [.adjustmentData, .fullSizePhoto, .fullSizeVideo].contains($0.type) }
        )
    }

    static func isScreenshot(_ asset: PHAsset) -> Bool {
        asset.mediaType == .image && asset.mediaSubtypes.contains(.photoScreenshot)
    }
}
