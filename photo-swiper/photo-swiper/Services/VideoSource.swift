import AVFoundation
import Photos

/// Turns a video item into something playable. The single place an `ImageReference` becomes
/// a stream, so the preview doesn't care whether it came from PhotoKit or the mock bundle.
@MainActor
enum VideoSource {
    /// Nil when the asset is gone or can't be fetched (e.g. iCloud is unreachable).
    static func playerItem(for item: LibraryItem) async -> AVPlayerItem? {
        switch item.image {
        case .bundled:
            // Mock videos are stills in the asset catalog; they all play the same sample clip.
            return Bundle.main.url(forResource: "mock-video", withExtension: "mp4").map(AVPlayerItem.init(url:))
        case .photoKit(let id):
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            return await photoKitItem(for: asset)
        }
    }

    private static func photoKitItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let manager = PHImageManager.default()
        let request = RequestBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                request.id = manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                    continuation.resume(returning: item)
                }
            }
        } onCancel: {
            if let id = request.id { manager.cancelImageRequest(id) }
        }
    }

    /// Lets the cancellation handler reach the request started inside the continuation.
    private final class RequestBox: @unchecked Sendable {
        var id: PHImageRequestID?
    }
}
