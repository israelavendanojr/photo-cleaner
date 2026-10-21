import CoreGraphics
import ImageIO

/// Computes image signals from one decoded image. `VisionImageAnalyzer` is the real one; tests fake it.
protocol ImageAnalyzing: Sendable {
    func analyze(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> ImageSignals
}

/// What image analysis found. A nil field means that signal couldn't be computed.
struct ImageSignals: Hashable, Sendable {
    var sharpness: Double?
    var exposure: ExposureStats?
    var aesthetic: Double?
    var isUtility: Bool?
}

extension AssetFeatures {
    mutating func apply(_ signals: ImageSignals) {
        sharpness = signals.sharpness
        exposure = signals.exposure
        aesthetic = signals.aesthetic
        isUtility = signals.isUtility
    }
}
