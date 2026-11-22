import Photos

/// Makes a flattened Live Photo's still in the user's library, when the bin is cleared (JUN-79).
///
/// With no key frame chosen, the still is the original's own file, byte for byte: the rendered one if it
/// was edited in Photos (so a crop or filter stays baked in), otherwise the camera's. That keeps its
/// metadata and loses nothing. It's saved with the original's creation date, location, favorite status
/// and albums (`LibraryCopy`), then fetched back to check it's there. Nothing is deleted here.
///
/// An iCloud-only original is downloaded first. That's Apple's iCloud, which the privacy copy allows,
/// and only for a photo the user chose to flatten.
struct PhotoKitPhotoEditor: PhotoEditing {
    func makeCopy(of item: LibraryItem, edit: PendingEdit, progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy {
        guard let live = edit.live, case .photoKit(let id) = item.image, let asset = PHAsset.byID([id])[id],
              asset.mediaType == .image, asset.mediaSubtypes.contains(.photoLive) else {
            throw EditError.unavailable
        }
        // A frame chosen from the motion comes with JUN-106.
        guard live.keyFrameTime == nil else { throw EditError.unsupported }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let still = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) else {
            throw EditError.unavailable
        }
        let suffix = (still.originalFilename as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory.appending(path: "flatten-\(UUID().uuidString).\(suffix.isEmpty ? "heic" : suffix)")
        defer { try? FileManager.default.removeItem(at: url) }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress($0 * 0.9) }
        do {
            try await PHAssetResourceManager.default().writeData(for: still, toFile: url, options: options)
        } catch {
            throw EditError.unavailable
        }
        try Task.checkCancellation()
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard bytes > 0 else { throw EditError.unavailable }

        let copyID = try await LibraryCopy.save(url, as: .photo, uniformTypeIdentifier: still.uniformTypeIdentifier, like: id)
        // Checked, and a still: never a Live Photo again.
        guard let copy = PHAsset.byID([copyID])[copyID], !copy.mediaSubtypes.contains(.photoLive) else { throw EditError.saveFailed }
        progress(1)
        return EditedCopy(id: copyID, bytes: bytes)
    }

    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> {
        Set(PHAsset.byID(Array(ids)).keys)
    }
}
