import AVFoundation
import OSLog
import Photos
import UniformTypeIdentifiers

/// Gets a library photo or video ready to share (JUN-8): its current version, as Photos shows it, in a
/// `share-` folder with its location removed.
///
/// - A photo is its rendered image at full quality in its own format (edits included). A Live Photo gives
///   its still only. The data request can be cancelled mid-download, which a resource write can't.
/// - A video is its rendered version too: slow motion and Cinematic as Photos plays them. Other videos are
///   copied without re-encoding. `ExportPlan` and `VideoEncoder` aren't used: sharing never trims or
///   compresses, and they can't render a slow-motion composition.
///
/// An iCloud-only item is downloaded first. That's Apple's iCloud, which the privacy copy allows, and only
/// for an item the user chose to share. Nothing in the library changes.
struct PhotoKitMediaSharer: MediaSharing {
    func prepare(_ item: LibraryItem) async throws -> URL {
        guard case .photoKit(let id) = item.image, let asset = PHAsset.byID([id])[id] else { throw ShareError.gone }
        let folder: URL
        do { folder = try ShareFiles.makeFolder() } catch { throw ShareError.exportFailed }
        do {
            let url = asset.mediaType == .video ? try await Self.video(asset, into: folder) : try await Self.photo(asset, into: folder)
            try Task.checkCancellation()
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            let nsError = error as NSError
            Self.log.error("Couldn't prepare a share: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            throw (error as? ShareError) ?? .exportFailed
        }
    }

    /// What a photo request delivers, carried across PhotoKit's callback.
    private struct PhotoResult: Sendable {
        let data: Data?
        let type: String?
        let needsDownload: Bool
    }

    private static func photo(_ asset: PHAsset, into folder: URL) async throws -> URL {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let manager = PHImageManager.default()
        let result: PhotoResult? = await VideoSource.cancellableRequest(
            start: { handler in
                manager.requestImageDataAndOrientation(for: asset, options: options) { data, type, _, info in
                    handler(PhotoResult(data: data, type: type, needsDownload: needsDownload(info)))
                }
            },
            cancel: { manager.cancelImageRequest($0) }
        )
        try Task.checkCancellation()
        guard let result, let data = result.data else { throw result?.needsDownload == true ? ShareError.downloadFailed : .exportFailed }

        let stripped = try ShareMetadata.strippingLocation(imageData: data)
        let original = PHAssetResource.assetResources(for: asset).first { $0.type == .photo }?.originalFilename
        let name = ShareFiles.fileName(original: original, type: result.type.flatMap(UTType.init), fallback: "Photo")
        let url = folder.appending(path: name)
        do { try stripped.write(to: url) } catch { throw ShareError.exportFailed }
        return url
    }

    /// The export session PhotoKit sets up, carried across its callback. Unchecked because the session
    /// isn't Sendable: it's handed over once, from PhotoKit's callback to the one task awaiting it, and
    /// only that task touches it afterwards.
    private struct SessionResult: @unchecked Sendable {
        let session: AVAssetExportSession?
        let needsDownload: Bool
    }

    private static func video(_ asset: PHAsset, into folder: URL) async throws -> URL {
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        // Slow motion and Cinematic come back as compositions, which only a real export renders.
        let isComposed = !asset.mediaSubtypes.isDisjoint(with: [.videoHighFrameRate, .videoCinematic])
        let preset = isComposed ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
        let manager = PHImageManager.default()
        let result: SessionResult? = await VideoSource.cancellableRequest(
            start: { handler in
                manager.requestExportSession(forVideo: asset, options: options, exportPreset: preset) { session, info in
                    handler(SessionResult(session: session, needsDownload: needsDownload(info)))
                }
            },
            cancel: { manager.cancelImageRequest($0) }
        )
        try Task.checkCancellation()
        guard let result, let session = result.session else { throw result?.needsDownload == true ? ShareError.downloadFailed : .exportFailed }

        session.metadata = ShareMetadata.withoutLocation(try await session.asset.load(.metadata))
        let original = PHAssetResource.assetResources(for: asset).first { $0.type == .video }?.originalFilename
        let url = folder.appending(path: ShareFiles.fileName(original: original, type: .quickTimeMovie, fallback: "Video"))
        try await session.export(to: url, as: .mov)
        return url
    }

    /// The request failed because the item is in iCloud, or a download was tried and failed.
    private static func needsDownload(_ info: [AnyHashable: Any]?) -> Bool {
        (info?[PHImageResultIsInCloudKey] as? Bool) == true || info?[PHImageErrorKey] != nil
    }

    private static let log = Logger.app(category: "share")
}
