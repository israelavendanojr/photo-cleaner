import Foundation
import Photos

/// How many bytes deleting an asset frees.
///
/// PhotoKit has no public size API. Each `PHAssetResource` carries an undocumented but long-stable
/// `fileSize` value; summing every resource (original, Live Photo video, edited render…) matches
/// what deletion removes. It's local metadata, so it works for iCloud-only assets without downloading.
enum FileSizeReader {
    static func bytes(for asset: PHAsset) -> Int64 {
        let total = PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { sum, resource in
            sum + ((resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
        return total > 0 ? total : estimate(for: asset)
    }

    /// Fallback if the key ever disappears: typical HEIC density and HEVC bitrate.
    private static func estimate(for asset: PHAsset) -> Int64 {
        switch asset.mediaType {
        case .video: Int64(asset.duration * 1_500_000)
        default: Int64(Double(asset.pixelWidth * asset.pixelHeight) * 0.3)
        }
    }
}
