#if DEBUG
@preconcurrency import Photos

/// The mock library's Live Photo: `mock-live.heic` and `mock-live.mov` in Resources, a real pair made by
/// `scripts/make-mock-live-photo.swift`, so previews and UI tests play it like one from the camera.
enum MockLivePhoto {
    /// Where the still sits in the clip, as the script writes it.
    static let keyFrameTime: TimeInterval = 1.25

    static var resourceURLs: [URL] {
        [("mock-live", "heic"), ("mock-live", "mov")].compactMap { Bundle.main.url(forResource: $0.0, withExtension: $0.1) }
    }

    @MainActor
    static func load(targetSize: CGSize) async -> PHLivePhoto? {
        let urls = resourceURLs
        guard urls.count == 2 else { return nil }
        return await VideoSource.cancellableRequest(
            start: { handler in
                PHLivePhoto.request(withResourceFileURLs: urls, placeholderImage: nil, targetSize: targetSize,
                                    contentMode: .aspectFit) { photo, info in
                    // A degraded version can come first; wait for the full one.
                    if photo != nil, (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                    handler(photo)
                }
            },
            cancel: { PHLivePhoto.cancelRequest(withRequestID: $0) }
        )
    }
}
#endif
