import Foundation
import ImageIO
import Photos
import UIKit

/// The library as the indexer sees it, through PhotoKit.
///
/// Uses its own `PHImageManager`, separate from `ThumbnailPipeline`: high-quality delivery only (no
/// degraded frames), about 512 px, and network access off, so iCloud-only originals are skipped
/// rather than downloaded. `PHImageManager` is thread-safe, so this needs no isolation.
final class PhotoKitIndexSource: IndexAssetSource, @unchecked Sendable {
    private static let targetSize = CGSize(width: 512, height: 512)

    private static let options: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        return options
    }()

    private let manager = PHImageManager()

    func currentAssets() async -> [IndexableAsset] {
        let result = PHAsset.fetchAssets(with: PhotoKitLibrary.fetchOptions(skipFavorites: false))
        var assets: [IndexableAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            let kind: IndexableAsset.Kind = if asset.mediaType == .video { .video }
                else if AssetMapper.isScreenshot(asset) { .screenshot }
                else { .photo }
            assets.append(IndexableAsset(
                id: asset.localIdentifier,
                createdAt: asset.creationDate ?? asset.modificationDate ?? .distantPast,
                modifiedAt: asset.modificationDate,
                kind: kind
            ))
        }
        return assets
    }

    func metadata(for ids: [LibraryItem.ID]) async -> [LibraryItem.ID: AssetFeatures] {
        guard !ids.isEmpty else { return [:] }
        var features: [LibraryItem.ID: AssetFeatures] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            features[asset.localIdentifier] = AssetMapper.features(for: asset)
        }
        return features
    }

    func image(for id: LibraryItem.ID) async -> AnalysisImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let once = Once()
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: Self.targetSize, contentMode: .aspectFit, options: Self.options) { image, _ in
                // High-quality delivery calls back once; the guard makes a second call harmless.
                guard once.claim() else { return }
                guard let image, let cgImage = image.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: AnalysisImage(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation)))
            }
        }
    }
}

/// True the first time only.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        self = switch orientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
