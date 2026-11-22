import CoreGraphics
import Foundation

/// Choosing a Live Photo's key photo from its motion (JUN-106). Pure, so the viewer's rules are tested
/// without a player.
///
/// The key photo's own frame flattens losslessly to the original still. Any other frame comes from the
/// motion, so the flatten records its time, and its size is an estimate.
enum KeyFrame {
    /// A HEIC photo's bytes per pixel: the density `FileSizeReader` estimates sizes with.
    static let bytesPerPixel = 0.3

    /// Whether `time` is the key photo's own frame: within a frame of it, since a finger can't land on an
    /// exact time. With no known key photo time, every frame is the original, and nothing is chosen.
    static func isOriginal(time: TimeInterval, photoTime: TimeInterval?, frameDuration: TimeInterval) -> Bool {
        guard let photoTime else { return true }
        return abs(time - photoTime) <= max(frameDuration, 0)
    }

    /// The flatten for the frame at `time`. The original frame keeps `stillBytes`, the still's real size,
    /// and no time. Choosing it again goes back to the lossless path. Any other frame keeps its time, and its
    /// size is estimated from its pixels (nil when they aren't known, which claims no savings).
    static func flatten(at time: TimeInterval, photoTime: TimeInterval?, frameDuration: TimeInterval,
                        frameSize: CGSize, stillBytes: Int64?) -> PendingEdit {
        guard !isOriginal(time: time, photoTime: photoTime, frameDuration: frameDuration) else {
            return PendingEdit(originalDuration: 0, live: LiveEdit(stillBytes: stillBytes))
        }
        let estimate: Int64? = frameSize.width > 0 && frameSize.height > 0
            ? Int64(frameSize.width * frameSize.height * bytesPerPixel)
            : nil
        return PendingEdit(originalDuration: 0, live: LiveEdit(keyFrameTime: time, stillBytes: estimate))
    }
}
