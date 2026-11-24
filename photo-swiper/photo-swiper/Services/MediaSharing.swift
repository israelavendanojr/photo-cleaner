import Foundation

/// Gets one photo or video ready for iOS's share sheet (JUN-8): its current version as a file in a fresh
/// `share-` folder in the temp directory, with its location removed (`ShareMetadata`). The view model asks
/// before showing the sheet, so an iCloud download shows on the card instead of stalling inside Messages.
///
/// Sharing never decides, keeps or deletes anything. `PhotoKitMediaSharer` is the real one;
/// `MockMediaSharer` backs the mock library.
protocol MediaSharing: Sendable {
    /// Exports `item` and returns the file. Throws `CancellationError` when the task is cancelled, or a
    /// `ShareError`, leaving no files behind either way. Who gets the file removes it (`ShareFiles.remove`).
    func prepare(_ item: LibraryItem) async throws -> URL
}

/// Why a share couldn't be prepared. Each is shown as a toast, and nothing else changes.
enum ShareError: Error, Equatable {
    /// It's no longer in the library.
    case gone
    /// It's in iCloud and couldn't be downloaded, e.g. while offline.
    case downloadFailed
    /// The file couldn't be written or exported.
    case exportFailed

    /// The toast's text.
    var message: String {
        switch self {
        case .gone: "It's no longer in your library."
        case .downloadFailed: "Couldn't download it. Check your connection and try again."
        case .exportFailed: "Couldn't get it ready to share. Try again."
        }
    }
}
