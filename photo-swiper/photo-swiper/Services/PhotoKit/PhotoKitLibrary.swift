import Foundation
import Photos

/// The user's real library, through PhotoKit.
///
/// Thread-safe: PhotoKit calls the change observer on a background queue, so the mutable
/// state below is guarded by `lock`.
final class PhotoKitLibrary: NSObject, PhotoLibraryProviding, @unchecked Sendable {
    private let lock = NSLock()
    /// Every photo and video, kept current so change details can report removals.
    private var allAssets: PHFetchResult<PHAsset>?
    private var listeners: [UUID: AsyncStream<Set<LibraryItem.ID>>.Continuation] = [:]

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: PhotoLibraryProviding

    func requestAccess() async -> LibraryAccess {
        // Returns the current status without prompting once the user has answered.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let access: LibraryAccess = switch status {
        case .authorized: .full
        case .limited: .limited
        default: .denied
        }
        if access != .denied { startObserving() }
        return access
    }

    func stats() async -> LibraryStats {
        let total = lock.withLock { allAssets?.count } ?? 0
        // Reviewed and freed totals need persistence, which comes later.
        return LibraryStats(totalItems: total, reviewedItems: 0, freedBytes: 0)
    }

    func delete(_ items: [LibraryItem]) async throws -> DeletionOutcome {
        let ids = items.map(\.id)
        var found: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            found.append(asset)
        }
        let foundIDs = Set(found.map(\.localIdentifier))
        let deletable = found.filter { $0.canPerform(.delete) }

        var outcome = DeletionOutcome()
        outcome.missing = ids.filter { !foundIDs.contains($0) }
        outcome.undeletable = found.filter { !$0.canPerform(.delete) }.map(\.localIdentifier)
        guard !deletable.isEmpty else { return outcome }

        // All or nothing: iOS shows its own confirmation for the whole request.
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(deletable as NSArray)
            }
        } catch {
            throw Self.isUserCancellation(error) ? DeletionError.cancelled : DeletionError.failed(error)
        }
        outcome.deleted = deletable.map(\.localIdentifier)
        return outcome
    }

    func vanishedItems() -> AsyncStream<Set<LibraryItem.ID>> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { listeners[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.withLock { self.listeners[id] = nil }
            }
        }
    }

    // MARK: Queries

    /// Photos and videos in the user's own library, newest first.
    static func fetchOptions(skipFavorites: Bool) -> PHFetchOptions {
        let options = PHFetchOptions()
        var format = "(mediaType == %d OR mediaType == %d)"
        if skipFavorites { format += " AND favorite == NO" }
        options.predicate = NSPredicate(format: format, PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Excludes shared albums and items synced from a computer, which can't be deleted here.
        options.includeAssetSourceTypes = .typeUserLibrary
        return options
    }

    // MARK: Internals

    private func startObserving() {
        let isNew = lock.withLock {
            guard allAssets == nil else { return false }
            allAssets = PHAsset.fetchAssets(with: Self.fetchOptions(skipFavorites: false))
            return true
        }
        if isNew { PHPhotoLibrary.shared().register(self) }
    }

    /// The cancel error has shipped under both the Photos and Cocoa domains, always code 3072.
    private static func isUserCancellation(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.code == PHPhotosError.Code.userCancelled.rawValue
            && (error.domain == PHPhotosErrorDomain || error.domain == NSCocoaErrorDomain)
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoKitLibrary: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let (removed, listeners) = lock.withLock { () -> (Set<LibraryItem.ID>, [AsyncStream<Set<LibraryItem.ID>>.Continuation]) in
            guard let before = allAssets, let details = changeInstance.changeDetails(for: before) else { return ([], []) }
            let after = details.fetchResultAfterChanges
            allAssets = after
            let removed: Set<LibraryItem.ID> = if details.hasIncrementalChanges {
                Set(details.removedObjects.map(\.localIdentifier))
            } else {
                // Too much changed for a diff; compare identifiers directly.
                Self.identifiers(in: before).subtracting(Self.identifiers(in: after))
            }
            return (removed, Array(self.listeners.values))
        }
        guard !removed.isEmpty else { return }
        for listener in listeners { listener.yield(removed) }
    }

    private static func identifiers(in result: PHFetchResult<PHAsset>) -> Set<String> {
        var ids = Set<String>(minimumCapacity: result.count)
        result.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        return ids
    }
}
