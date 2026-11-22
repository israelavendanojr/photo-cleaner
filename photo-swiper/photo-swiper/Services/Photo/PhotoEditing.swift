import Foundation

/// Makes a Live Photo's still copy in the library, when the bin is cleared (JUN-79). Like `VideoEditing`, it
/// never deletes anything: the original goes with the rest of the bin, in `PhotoKitLibrary.delete`, only
/// once its still is saved and checked. `PhotoKitPhotoEditor` is the real one; `MockPhotoEditor` backs the
/// mock library.
protocol PhotoEditing: Sendable {
    /// Saves `item`'s still as a new photo with the original's creation date, location, favorite status and
    /// albums, and checks it's in the library. `edit.live` says which still. `progress` goes from 0 to 1.
    func makeCopy(of item: LibraryItem, edit: PendingEdit, progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy

    /// The copies among `ids` that are still in the library, so a clear that was interrupted after saving
    /// one goes straight to the delete instead of making it again.
    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID>
}
