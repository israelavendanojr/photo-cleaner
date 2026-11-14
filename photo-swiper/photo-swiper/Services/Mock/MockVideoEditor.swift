#if DEBUG
import Foundation

/// Pretends to make edited copies for the mock library: a short wait with progress, then a copy as
/// large as the edit's estimate. Nothing is written anywhere.
struct MockVideoEditor: VideoEditing {
    var duration: Duration = .seconds(1.5)

    func makeCopy(of item: LibraryItem, edit: PendingEdit, levels: CompressionLevels,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy {
        let steps = 10
        for step in 1...steps {
            try await Task.sleep(for: duration / steps)
            progress(Double(step) / Double(steps))
        }
        return EditedCopy(id: "\(item.id)-edited-\(UUID().uuidString.prefix(8))", bytes: edit.estimatedBytes(from: item.bytes))
    }

    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> { ids }
}
#endif
