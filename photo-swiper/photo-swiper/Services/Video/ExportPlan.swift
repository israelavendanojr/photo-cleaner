import Foundation

/// How one edited video is exported when the bin is confirmed: always in one pass, so it's never
/// encoded twice.
///
/// A trim alone copies the kept part without re-encoding (cuts snap to keyframes, which is fine).
/// Any compression re-encodes once, with the trim applied while the source is read.
enum ExportPlan: Equatable, Sendable {
    case passthrough(TrimRange)
    case reencode(TrimRange?, CompressionSettings)

    /// Nil for an empty edit, which has nothing to export.
    static func make(_ edit: PendingEdit, source: VideoSourceInfo, levels: CompressionLevels) -> ExportPlan? {
        if let level = edit.compression {
            return .reencode(edit.range, CompressionSettings.resolve(level, levels: levels, source: source))
        }
        return edit.range.map(ExportPlan.passthrough)
    }

    /// The copy's estimated size, logged beside the real one.
    func estimatedBytes(originalBytes: Int64, originalDuration: TimeInterval) -> Int64 {
        switch self {
        case .passthrough(let range):
            PendingEdit(range: range, originalDuration: originalDuration).estimatedBytes(from: originalBytes)
        case .reencode(let range, let settings):
            settings.estimatedBytes(seconds: range?.length ?? originalDuration)
        }
    }

    /// "passthrough" or "reencode", for the log.
    var name: String {
        switch self {
        case .passthrough: "passthrough"
        case .reencode: "reencode"
        }
    }
}
