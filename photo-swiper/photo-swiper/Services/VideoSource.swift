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
            guard let asset = PHAsset.byID([id])[id] else { return nil }
            return await photoKitItem(for: asset)
        }
    }

    private static func photoKitItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let manager = PHImageManager.default()
        return await cancellableRequest(
            start: { handler in manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in handler(item) } },
            cancel: { manager.cancelImageRequest($0) }
        )
    }

    /// Runs a PhotoKit request and waits for its result handler. Resumes exactly once: with the first
    /// result delivered, or with nil as soon as the task is cancelled, since PhotoKit may never call
    /// back for a cancelled request. A request started after the cancel is cancelled straight away.
    nonisolated static func cancellableRequest<T>(
        start: (@escaping (T?) -> Void) -> PHImageRequestID,
        cancel: @escaping (PHImageRequestID) -> Void
    ) async -> T? {
        let request = RequestBox<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request.begin(continuation) else { return }
                let id = start { request.finish($0) }
                if request.started(id) { cancel(id) }
            }
        } onCancel: {
            if let id = request.cancel() { cancel(id) }
        }
    }

    /// Shared by the request, its result handler, and the cancellation handler, which can run on
    /// different threads in any order. Guarded by `lock`; the continuation is resumed only once.
    private final class RequestBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?
        private var id: PHImageRequestID?
        private var isCancelled = false

        /// Holds the continuation, or resumes it with nil if the task was already cancelled.
        /// False when there's nothing to start.
        func begin(_ continuation: CheckedContinuation<T?, Never>) -> Bool {
            let cancelled = lock.withLock {
                if !isCancelled { self.continuation = continuation }
                return isCancelled
            }
            if cancelled { continuation.resume(returning: nil) }
            return !cancelled
        }

        /// Records the request. True if a cancel came in meanwhile, so the caller cancels it now.
        func started(_ id: PHImageRequestID) -> Bool {
            lock.withLock {
                self.id = id
                return isCancelled
            }
        }

        func finish(_ value: T?) {
            take()?.resume(returning: value)
        }

        /// Ends the wait with nil. Returns the request to cancel, if it has started.
        func cancel() -> PHImageRequestID? {
            let (id, continuation) = lock.withLock { () -> (PHImageRequestID?, CheckedContinuation<T?, Never>?) in
                isCancelled = true
                defer { self.continuation = nil }
                return (self.id, self.continuation)
            }
            continuation?.resume(returning: nil)
            return id
        }

        private func take() -> CheckedContinuation<T?, Never>? {
            lock.withLock {
                defer { continuation = nil }
                return continuation
            }
        }
    }
}
