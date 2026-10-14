import Foundation
import Photos

/// `PHAsset` → `LibraryItem`.
enum AssetMapper {
    static func item(for asset: PHAsset, location: String?) -> LibraryItem {
        LibraryItem(
            id: asset.localIdentifier,
            kind: asset.mediaType == .video ? .video(duration: asset.duration) : .photo,
            date: asset.creationDate ?? asset.modificationDate ?? .distantPast,
            location: location,
            bytes: FileSizeReader.bytes(for: asset),
            flags: isScreenshot(asset) ? [.screenshot] : [],
            isFavorite: asset.isFavorite,
            image: .photoKit(localIdentifier: asset.localIdentifier)
        )
    }

    static func isScreenshot(_ asset: PHAsset) -> Bool {
        asset.mediaType == .image && asset.mediaSubtypes.contains(.photoScreenshot)
    }
}
