@preconcurrency import Photos

/// Turns a Live Photo item into something the full-screen viewer can play (JUN-105). The single place an
/// `ImageReference` becomes a `PHLivePhoto`, like `VideoSource` for videos, so the viewer doesn't care
/// whether it came from PhotoKit or the mock bundle.
@MainActor
enum LivePhotoSource {
    /// The still and its motion, at about `targetSize` pixels. Nil when the asset is gone or isn't a Live
    /// Photo, or its motion can't be fetched (e.g. iCloud is unreachable). The motion may come from iCloud:
    /// that's Apple's, which the privacy copy allows, and only for a photo the user is holding to play.
    static func livePhoto(for item: LibraryItem, targetSize: CGSize) async -> PHLivePhoto? {
        switch item.image {
        case .bundled:
            #if DEBUG
            return await MockLivePhoto.load(targetSize: targetSize)
            #else
            return nil
            #endif
        case .photoKit(let id):
            guard let asset = PHAsset.byID([id])[id], asset.mediaSubtypes.contains(.photoLive) else { return nil }
            let options = PHLivePhotoRequestOptions()
            options.isNetworkAccessAllowed = true
            // One result, not a degraded one first: the viewer only shows it while playing.
            options.deliveryMode = .highQualityFormat
            let manager = PHImageManager.default()
            return await VideoSource.cancellableRequest(
                start: { handler in
                    manager.requestLivePhoto(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { photo, _ in
                        handler(photo)
                    }
                },
                cancel: { manager.cancelImageRequest($0) }
            )
        }
    }
}
