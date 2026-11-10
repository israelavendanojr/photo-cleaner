import Foundation
import OSLog
import Photos

/// How many bytes deleting an asset frees.
///
/// PhotoKit has no public size API. Each `PHAssetResource` carries an undocumented but long-stable
/// `fileSize` value; summing every resource (original, Live Photo video, edited render…) matches
/// what deletion removes. It's local metadata, so it works for iCloud-only assets without downloading.
/// It's undocumented KVC (worth a note for App Review), so Debug builds log once if it stops resolving.
enum FileSizeReader {
    static func bytes(for asset: PHAsset) -> Int64 {
        bytes(for: asset, resources: PHAssetResource.assetResources(for: asset))
    }

    /// For callers that already fetched the asset's resources.
    static func bytes(for asset: PHAsset, resources: [PHAssetResource]) -> Int64 {
        let total = resources.reduce(Int64(0)) { sum, resource in
            let size = (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value
            #if DEBUG
            if size == nil { MissingKeyLog.once() }
            #endif
            return sum + (size ?? 0)
        }
        return total > 0 ? total : estimate(for: asset)
    }

    #if DEBUG
    /// Notes the first time `fileSize` doesn't resolve, so an iOS change that drops it is noticed.
    private enum MissingKeyLog {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var logged = false

        static func once() {
            let first = lock.withLock {
                defer { logged = true }
                return !logged
            }
            guard first else { return }
            Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "size")
                .warning("PHAssetResource fileSize didn't resolve; sizes fall back to estimates")
        }
    }
    #endif

    /// Fallback if the key ever disappears: typical HEIC density and HEVC bitrate.
    private static func estimate(for asset: PHAsset) -> Int64 {
        switch asset.mediaType {
        case .video: Int64(asset.duration * 1_500_000)
        default: Int64(Double(asset.pixelWidth * asset.pixelHeight) * 0.3)
        }
    }
}
