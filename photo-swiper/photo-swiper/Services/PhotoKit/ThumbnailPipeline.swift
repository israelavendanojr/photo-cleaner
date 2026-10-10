import Photos
import UIKit

/// Loads and pre-caches PhotoKit images for cards and tiles.
///
/// One shared `PHCachingImageManager` serves every view. Requests use opportunistic delivery, so an
/// iCloud-only photo shows a degraded local version first and the full one once it downloads.
/// Memory stays flat because only a small window of upcoming cards is ever pre-cached.
@MainActor
final class ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    /// Caps decoded card images (~6 MB each) without visible softness on a phone-sized card.
    private static let maxLongEdge: CGFloat = 1600
    /// Request sizes are rounded up to this so preheat and display requests hit the same cache entry.
    private static let bucket: CGFloat = 128

    private static let options: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }()

    private let manager = PHCachingImageManager()
    private var assets: [String: PHAsset] = [:]
    /// What's currently pre-cached, by local identifier.
    private var preheated: [String: CGSize] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [manager] _ in
            manager.stopCachingImagesForAllAssets()
        }
    }

    /// The pixel size to request for a view of `size` points.
    nonisolated static func pixelSize(for size: CGSize, scale: CGFloat) -> CGSize {
        var width = size.width * scale
        var height = size.height * scale
        let longEdge = max(width, height)
        if longEdge > maxLongEdge {
            width *= maxLongEdge / longEdge
            height *= maxLongEdge / longEdge
        }
        let round = { (value: CGFloat) in max(bucket, (value / bucket).rounded(.up) * bucket) }
        return CGSize(width: round(width), height: round(height))
    }

    /// Yields a degraded image first when one exists, then the final image, then finishes.
    /// Ending the stream (e.g. the view's task is cancelled) cancels the request.
    func images(for id: String, pixelSize: CGSize) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = asset(for: id) else {
                continuation.finish()
                return
            }
            let request = manager.requestImage(
                for: asset, targetSize: pixelSize, contentMode: .aspectFill, options: Self.options
            ) { image, info in
                if let image { continuation.yield(image) }
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if !isDegraded || info?[PHImageErrorKey] != nil || info?[PHImageCancelledKey] as? Bool == true {
                    continuation.finish()
                }
            }
            continuation.onTermination = { [manager] _ in manager.cancelImageRequest(request) }
        }
    }

    /// Pre-caches exactly these images and releases everything else that was pre-cached.
    func preheat(_ wanted: [String: CGSize]) {
        let stale = preheated.filter { wanted[$0.key] != $0.value }
        let fresh = wanted.filter { preheated[$0.key] != $0.value }
        for (size, ids) in Self.group(stale) {
            manager.stopCachingImages(for: ids.compactMap(asset(for:)), targetSize: size.cgSize, contentMode: .aspectFill, options: Self.options)
        }
        for (size, ids) in Self.group(fresh) {
            manager.startCachingImages(for: ids.compactMap(asset(for:)), targetSize: size.cgSize, contentMode: .aspectFill, options: Self.options)
        }
        preheated = wanted
        // Keep the asset lookup cache to what's in use.
        if assets.count > 300 { assets = assets.filter { wanted[$0.key] != nil } }
    }

    private func asset(for id: String) -> PHAsset? {
        if let asset = assets[id] { return asset }
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        assets[id] = asset
        return asset
    }

    private struct SizeKey: Hashable {
        let width: CGFloat
        let height: CGFloat
        var cgSize: CGSize { CGSize(width: width, height: height) }
    }

    /// PhotoKit caches per target size, so start/stop calls are batched by size.
    private static func group(_ sizes: [String: CGSize]) -> [SizeKey: [String]] {
        Dictionary(grouping: sizes.keys) { SizeKey(width: sizes[$0]!.width, height: sizes[$0]!.height) }
    }
}

extension ImageReference {
    /// The PhotoKit identifier, for references that point into the library.
    var localIdentifier: String? {
        if case .photoKit(let id) = self { id } else { nil }
    }
}
