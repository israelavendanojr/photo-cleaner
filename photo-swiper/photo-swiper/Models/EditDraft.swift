import Foundation

/// The full-screen video's edit, against what's saved for the video: the trim handles (a `TrimDraft`)
/// and the compression level (JUN-50).
///
/// Leaving the viewer asks first when either differs from what's saved. Saving gives the `PendingEdit`
/// to queue, or nil when there's neither a trim nor a level left, which removes any pending edit.
struct EditDraft: Equatable {
    let duration: TimeInterval
    let saved: PendingEdit?
    /// The handles. Nil when trimming isn't offered (the trimmer is off, or the clip is too short); a
    /// saved trim is then kept as it is.
    var trim: TrimDraft?
    /// The chosen level, nil for None.
    private(set) var compression: CompressionLevel?

    /// `canTrim` false leaves the strip a plain seek bar.
    init(duration: TimeInterval, saved: PendingEdit? = nil, canTrim: Bool = true) {
        self.duration = max(duration, 0)
        self.saved = saved
        trim = canTrim && TrimDraft.canTrim(duration: duration) ? TrimDraft(duration: duration, saved: saved?.range) : nil
        compression = saved?.compression
    }

    /// The part kept: the handles', or the saved trim when there are no handles.
    var range: TrimRange? {
        guard let trim else { return saved?.range }
        return trim.isTrimmed ? trim.range : nil
    }

    var isTrimmed: Bool { range != nil }
    /// Trimmed, compressed, or both: the summary shows.
    var isEdited: Bool { isTrimmed || compression != nil }

    var hasUnsavedChanges: Bool {
        (trim?.hasUnsavedChanges ?? false) || compression != saved?.compression
    }

    /// None removes the compression and leaves the trim.
    mutating func setCompression(_ level: CompressionLevel?) {
        compression = level
    }

    /// Back to what's saved, handles and level.
    mutating func reset() {
        trim?.reset()
        compression = saved?.compression
    }

    /// What saving gives. `compressedBytes` is the estimate for the chosen level after the trim; it's
    /// dropped when there's no level. Nil when nothing is left to do.
    func result(compressedBytes: Int64?) -> PendingEdit? {
        let edit = PendingEdit(range: range, originalDuration: duration, compression: compression,
                               compressedBytes: compression == nil ? nil : compressedBytes)
        return edit.isEmpty ? nil : edit
    }
}
