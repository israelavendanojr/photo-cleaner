import CoreGraphics
import Foundation
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
    /// A `FeaturePrint`'s bytes. Kept beside `AssetFeatures`, not in it, so it never reaches saved decisions.
    var featurePrint: Data?
}

extension AssetFeatures {
    mutating func apply(_ signals: ImageSignals) {
        sharpness = signals.sharpness
        exposure = signals.exposure
        aesthetic = signals.aesthetic
        isUtility = signals.isUtility
    }
}
