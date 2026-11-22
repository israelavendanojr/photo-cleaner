import Foundation

/// Makes a video's edited copy in the library. It never deletes anything: the original is deleted
/// with the rest of the bin, in `PhotoKitLibrary.delete`, only once its copy is saved and checked.
/// `PhotoKitVideoEditor` is the real one; `MockVideoEditor` backs the mock library.
protocol VideoEditing: Sendable {
    /// Exports `item` once with `edit` applied, saves the copy with the original's creation date, location,
    /// favorite status and albums, and checks it's in the library. `progress` goes from 0 to 1.
    func makeCopy(of item: LibraryItem, edit: PendingEdit, levels: CompressionLevels,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy

    /// The copies among `ids` that are still in the library, so a confirm that was interrupted after
    /// saving one goes straight to the delete instead of exporting again.
    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID>
}

/// A saved, checked copy.
struct EditedCopy: Equatable, Sendable {
    let id: LibraryItem.ID
    /// The copy's real size.
    let bytes: Int64
}

/// Why an edited copy (a video's, or a Live Photo's still) couldn't be made.
typealias EditError = VideoEditError

enum VideoEditError: Error, Equatable {
    /// The original isn't in the library (or isn't the kind the edit is for), or couldn't be downloaded from iCloud.
    case unavailable
    /// Slow-motion and Cinematic videos aren't edited.
    case unsupported
    case exportFailed
    /// Saving the copy failed, or it wasn't in the library afterwards.
    case saveFailed
}
