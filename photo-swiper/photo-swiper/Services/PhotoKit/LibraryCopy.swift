import OSLog
import Photos

/// Saves an edited copy next to its original: a trimmed or compressed video (`PhotoKitVideoEditor`) or a
/// flattened Live Photo's still (`PhotoKitPhotoEditor`). Only creates; the original is deleted with the
/// rest of the bin, in `PhotoKitLibrary.delete`, once the copy is checked.
enum LibraryCopy {
    private static let log = Logger.app(category: "edit")

    /// Saves the file at `url` as a new asset of `type` with the original's creation date, location,
    /// favorite status and albums, and returns its identifier. The file is moved into the library. The
    /// original is fetched again inside the change block, where PhotoKit wants its reads.
    static func save(_ url: URL, as type: PHAssetResourceType, uniformTypeIdentifier: String? = nil,
                     like originalID: LibraryItem.ID) async throws -> LibraryItem.ID {
        let created = CreatedID()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let original = PHAsset.byID([originalID])[originalID] else { return }
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                options.uniformTypeIdentifier = uniformTypeIdentifier
                request.addResource(with: type, fileURL: url, options: options)
                request.creationDate = original.creationDate
                request.location = original.location
                request.isFavorite = original.isFavorite
                guard let placeholder = request.placeholderForCreatedAsset else { return }
                created.set(placeholder.localIdentifier)
                // The user's own albums the original is in; smart albums fill themselves.
                PHAssetCollection.fetchAssetCollectionsContaining(original, with: .album, options: nil).enumerateObjects { album, _, _ in
                    guard album.canPerform(.addContent) else { return }
                    PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
                }
            }
        } catch {
            log.error("Saving an edited copy failed: \(error)")
            throw EditError.saveFailed
        }
        guard let id = created.value else { throw EditError.saveFailed }
        return id
    }
}

/// The new asset's identifier, handed out of PhotoKit's change block. The lock makes it safe to set
/// there and read after.
private final class CreatedID: @unchecked Sendable {
    private let lock = NSLock()
    private var id: String?

    var value: String? { lock.withLock { id } }
    func set(_ value: String) { lock.withLock { id = value } }
}
