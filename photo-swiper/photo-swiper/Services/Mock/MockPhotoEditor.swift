#if DEBUG
import Foundation

/// Pretends to flatten Live Photos for the mock library: a short wait with progress, then a still as large
/// as the flatten's estimate. Nothing is written anywhere.
struct MockPhotoEditor: PhotoEditing {
    var duration: Duration = .seconds(0.8)

    func makeCopy(of item: LibraryItem, edit: PendingEdit, progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy {
        let steps = 5
        for step in 1...steps {
            try await Task.sleep(for: duration / steps)
            progress(Double(step) / Double(steps))
        }
        return EditedCopy(id: "\(item.id)-still-\(UUID().uuidString.prefix(8))", bytes: edit.estimatedBytes(from: item.bytes))
    }

    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> { ids }
}
#endif
