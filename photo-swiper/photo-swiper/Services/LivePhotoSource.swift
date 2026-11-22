@preconcurrency import Photos

/// Turns a Live Photo item into something the full-screen viewer can play (JUN-105). The single place an
/// `ImageReference` becomes a `PHLivePhoto`, like `VideoSource` for videos, so the viewer doesn't care
/// whether it came from PhotoKit or the mock bundle.
@MainActor
enum LivePhotoSource {
    /// The still and its motion, at about `targetSize` pixels. Nil when the asset is gone or isn't a Live
    /// Photo, or its motion can't be fetched (e.g. iCloud is unreachable). The motion may come from iCloud,
    /// for a Live Photo opened full screen so a hold plays at once: that's Apple's, which the privacy copy allows.
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
                    manager.requestLivePhoto(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { photo, info in
                        // High quality should mean one result, but a degraded one would stick: wait past it.
                        if photo != nil, (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                        handler(photo)
                    }
                },
                cancel: { manager.cancelImageRequest($0) }
            )
        }
    }

    /// The size of the still a flatten keeps (JUN-79): the one Photos shows, rendered if it was edited there.
    /// What flattening saves is the item's size less this. Nil when it can't be read; metadata only, nothing
    /// is downloaded.
    static func stillBytes(for item: LibraryItem) -> Int64? {
        switch item.image {
        case .bundled:
            #if DEBUG
            // The mock's still is about two fifths of its Live Photo, a typical share.
            return item.bytes * 2 / 5
            #else
            return nil
            #endif
        case .photoKit(let id):
            guard let asset = PHAsset.byID([id])[id] else { return nil }
            let resources = PHAssetResource.assetResources(for: asset)
            let still = resources.first { $0.type == .fullSizePhoto } ?? resources.first { $0.type == .photo }
            return still.flatMap(FileSizeReader.bytes(of:))
        }
    }
}
