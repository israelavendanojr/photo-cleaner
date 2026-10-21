import CoreGraphics
import ImageIO
import OSLog
import Vision

/// Sharpness and exposure from Accelerate, plus Vision's aesthetics score and utility flag.
///
/// Everything runs on device with built-in models. If Vision fails (it can on the simulator), the
/// aesthetic fields stay nil and the pixel signals are still kept.
struct VisionImageAnalyzer: ImageAnalyzing {
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "index")

    func analyze(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> ImageSignals {
        var signals = ImageSignals()
        // Sharpness keeps the best tile and exposure is a histogram, so neither depends on orientation.
        if let gray = GrayscaleImage(image, longEdge: Sharpness.longEdge) {
            signals.sharpness = Sharpness.score(gray)
            signals.exposure = Exposure.stats(gray)
        }
        do {
            let observation = try await CalculateImageAestheticsScoresRequest().perform(on: image, orientation: orientation)
            signals.aesthetic = Double(observation.overallScore)
            signals.isUtility = observation.isUtility
        } catch {
            Self.log.error("Aesthetics request failed: \(error)")
        }
        return signals
    }
}
