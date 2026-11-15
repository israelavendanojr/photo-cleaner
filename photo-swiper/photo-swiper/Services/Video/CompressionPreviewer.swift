import AVFoundation
import Observation
import OSLog

/// Short samples of a video at each compression level, for the full-screen viewer's level popup (JUN-50).
///
/// A sample is about `sampleLength` seconds around the playhead, kept inside the trim, encoded with the
/// level's real settings by the same `VideoEncoder` the bin uses, so it looks like the copy will. Samples
/// are cached per level for the viewer's session, so switching back is instant; picking another level
/// while one is encoding cancels it. `clear()` deletes the files when the viewer closes.
@Observable
@MainActor
final class CompressionPreviewer {
    nonisolated static let sampleLength: TimeInterval = 3

    /// The level being shown or encoded; nil shows the original.
    private(set) var level: CompressionLevel?
    /// A sample for `level` is being encoded.
    private(set) var isEncoding = false
    /// The sample for `level`, once it's ready.
    private(set) var sampleURL: URL?
    /// The part of the video the current sample covers.
    private(set) var window: TrimRange?

    @ObservationIgnored private var cache: [CompressionLevel: (url: URL, window: TrimRange)] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let log = Logger.app(category: "edit")

    /// About `length` seconds around `time`, inside `range`; all of `range` when it's shorter.
    nonisolated static func window(around time: TimeInterval, within range: TrimRange, length: TimeInterval = sampleLength) -> TrimRange {
        guard range.length > length else { return range }
        let start = min(max(time - length / 2, range.start), range.end - length)
        return TrimRange(start: start, end: start + length)
    }

    /// Shows `level`'s sample, encoding it first unless it's cached. Nil goes back to the original.
    func show(_ level: CompressionLevel?, asset: AVAsset?, settings: CompressionSettings?, around time: TimeInterval, within range: TrimRange) {
        task?.cancel()
        task = nil
        self.level = level
        guard let level, let asset, let settings else {
            isEncoding = false
            sampleURL = nil
            window = nil
            return
        }
        if let cached = cache[level] {
            isEncoding = false
            sampleURL = cached.url
            window = cached.window
            return
        }
        let window = Self.window(around: time, within: range)
        let url = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString).mov")
        isEncoding = true
        sampleURL = nil
        self.window = window
        task = Task { [weak self] in
            do {
                try await VideoEncoder.encode(asset, range: window, settings: settings, to: url) { _ in }
                guard let self, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                cache[level] = (url, window)
                guard self.level == level else { return }
                isEncoding = false
                sampleURL = url
            } catch {
                try? FileManager.default.removeItem(at: url)
                guard let self, !Task.isCancelled, self.level == level else { return }
                log.error("Couldn't make a preview sample: \(error)")
                isEncoding = false
            }
        }
    }

    /// Stops any encode and deletes every sample.
    func clear() {
        task?.cancel()
        task = nil
        for sample in cache.values { try? FileManager.default.removeItem(at: sample.url) }
        cache = [:]
        level = nil
        isEncoding = false
        sampleURL = nil
        window = nil
    }
}
