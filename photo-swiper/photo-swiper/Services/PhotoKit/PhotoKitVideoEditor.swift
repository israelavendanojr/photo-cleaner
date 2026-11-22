import AVFoundation
import OSLog
import Photos

/// Makes edited copies of videos in the user's library, when the bin is confirmed (JUN-7, JUN-50).
///
/// Each video is exported once (`ExportPlan`): a trim alone without re-encoding, any compression in one
/// `VideoEncoder` pass. The copy is saved with the original's creation date, location, favorite status
/// and albums (`LibraryCopy`), then fetched back to check it's there. Nothing is deleted here; the original goes with
/// the rest of the bin, in `PhotoKitLibrary.delete`.
///
/// An iCloud-only original is downloaded first. That's Apple's iCloud, which the privacy copy allows,
/// and only for a video the user chose to edit.
struct PhotoKitVideoEditor: VideoEditing {
    private static let log = Logger.app(category: "edit")
    /// Share of the progress bar that downloading the original takes.
    private static let loadShare = 0.2

    func makeCopy(of item: LibraryItem, edit: PendingEdit, levels: CompressionLevels,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy {
        guard case .photoKit(let id) = item.image, let asset = PHAsset.byID([id])[id], asset.mediaType == .video else {
            throw VideoEditError.unavailable
        }
        // Slow-motion and Cinematic videos come back as compositions; they aren't offered for editing.
        guard asset.mediaSubtypes.isDisjoint(with: [.videoHighFrameRate, .videoCinematic]) else { throw VideoEditError.unsupported }

        let source = try await Self.loadAsset(asset) { progress($0 * Self.loadShare) }
        let info = try await VideoSourceInfo.load(from: source, fallbackBytes: item.bytes)
        guard let plan = ExportPlan.make(edit, source: info, levels: levels) else { throw VideoEditError.exportFailed }

        let url = FileManager.default.temporaryDirectory.appending(path: "edit-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let exportProgress: @Sendable (Double) -> Void = { progress(Self.loadShare + $0 * (0.95 - Self.loadShare)) }
        let started = Date.now
        switch plan {
        case .passthrough(let range):
            try await Self.passthrough(source, range: range, to: url, progress: exportProgress)
        case .reencode(let range, let settings):
            try await VideoEncoder.encode(source, range: range, settings: settings, to: url, progress: exportProgress)
        }
        try Task.checkCancellation()
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard bytes > 0 else { throw VideoEditError.exportFailed }

        let copyID = try await LibraryCopy.save(url, as: .video, like: id)
        guard !PHAsset.byID([copyID]).isEmpty else { throw VideoEditError.saveFailed }

        // Sizes and timings only, never identifiers, so levels can be tuned from a device's log.
        let estimate = plan.estimatedBytes(originalBytes: item.bytes, originalDuration: edit.originalDuration)
        Self.log.info("""
        Edit export \(plan.name, privacy: .public) \(edit.compression?.rawValue ?? "none", privacy: .public): \
        original \(item.bytes, privacy: .public) B, estimate \(estimate, privacy: .public) B, \
        real \(bytes, privacy: .public) B, \(Date.now.timeIntervalSince(started), format: .fixed(precision: 1), privacy: .public) s
        """)
        progress(1)
        return EditedCopy(id: copyID, bytes: bytes)
    }

    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> {
        Set(PHAsset.byID(Array(ids)).keys)
    }

    // MARK: Steps

    /// The original as it is in Photos (with any Photos edits), downloaded from iCloud if need be.
    private static func loadAsset(_ asset: PHAsset, progress: @escaping @Sendable (Double) -> Void) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.progressHandler = { value, _, _, _ in progress(value) }
        let manager = PHImageManager.default()
        let loaded: AVAsset? = await VideoSource.cancellableRequest(
            start: { handler in manager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in handler(avAsset) } },
            cancel: { manager.cancelImageRequest($0) }
        )
        try Task.checkCancellation()
        guard let loaded else { throw VideoEditError.unavailable }
        return loaded
    }

    /// Copies the kept part without re-encoding. It's quick, so it reports only when it's done.
    private static func passthrough(_ asset: AVAsset, range: TrimRange, to url: URL,
                                    progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoEditError.exportFailed
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 600),
                                        end: CMTime(seconds: range.end, preferredTimescale: 600))
        try await session.export(to: url, as: .mov)
        progress(1)
    }
}
