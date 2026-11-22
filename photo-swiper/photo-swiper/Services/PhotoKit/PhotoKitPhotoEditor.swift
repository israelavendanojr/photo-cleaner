import Photos
import UniformTypeIdentifiers

/// Makes a flattened Live Photo's still in the user's library, when the bin is cleared (JUN-79, JUN-106).
///
/// With no key frame chosen, the still is the original's own file, byte for byte: the rendered one if it
/// was edited in Photos (so a crop or filter stays baked in), otherwise the camera's. That keeps its
/// metadata and loses nothing. With a key frame chosen, it's that exact frame of the motion (the rendered
/// motion, if edited), upright, as HEIC, carrying the original still's metadata (`FrameStill`).
///
/// Either way it's saved with the original's creation date, location, favorite status and albums
/// (`LibraryCopy`), then fetched back to check it's there and isn't Live. Nothing is deleted here.
///
/// An iCloud-only original is downloaded first. That's Apple's iCloud, which the privacy copy allows,
/// and only for a photo the user chose to flatten.
struct PhotoKitPhotoEditor: PhotoEditing {
    func makeCopy(of item: LibraryItem, edit: PendingEdit, progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy {
        guard let live = edit.live, case .photoKit(let id) = item.image, let asset = PHAsset.byID([id])[id],
              asset.mediaType == .image, asset.mediaSubtypes.contains(.photoLive) else {
            throw EditError.unavailable
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let still = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) else {
            throw EditError.unavailable
        }

        var temporary: [URL] = []
        defer { temporary.forEach { try? FileManager.default.removeItem(at: $0) } }
        let stillURL = try await Self.write(still, progress: { progress($0 * (live.keyFrameTime == nil ? 0.9 : 0.3)) })
        temporary.append(stillURL)

        let url: URL
        let type: String
        if let time = live.keyFrameTime {
            guard let motion = resources.first(where: { $0.type == .fullSizePairedVideo })
                ?? resources.first(where: { $0.type == .pairedVideo }) else {
                throw EditError.unavailable
            }
            let videoURL = try await Self.write(motion, progress: { progress(0.3 + $0 * 0.5) })
            temporary.append(videoURL)
            url = Self.temporaryURL(suffix: "heic")
            temporary.append(url)
            _ = try await FrameStill.write(frameOf: videoURL, at: time, metadata: FrameStill.metadata(ofStillAt: stillURL), to: url)
            type = UTType.heic.identifier
        } else {
            url = stillURL
            type = still.uniformTypeIdentifier
        }
        try Task.checkCancellation()
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard bytes > 0 else { throw EditError.unavailable }

        let copyID = try await LibraryCopy.save(url, as: .photo, uniformTypeIdentifier: type, like: id)
        // Checked, and a still: never a Live Photo again.
        guard let copy = PHAsset.byID([copyID])[copyID], !copy.mediaSubtypes.contains(.photoLive) else { throw EditError.saveFailed }
        progress(1)
        return EditedCopy(id: copyID, bytes: bytes)
    }

    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> {
        Set(PHAsset.byID(Array(ids)).keys)
    }

    /// Writes `resource` to a new temporary file, downloading it from iCloud if need be.
    private static func write(_ resource: PHAssetResource, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let suffix = (resource.originalFilename as NSString).pathExtension
        let url = temporaryURL(suffix: suffix.isEmpty ? "dat" : suffix)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress($0) }
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw EditError.unavailable
        }
        return url
    }

    private static func temporaryURL(suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "flatten-\(UUID().uuidString).\(suffix)")
    }
}
