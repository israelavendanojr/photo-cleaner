import CoreGraphics
import Foundation
import ImageIO
import OSLog
import Vision

/// Sharpness and exposure from Accelerate, plus Vision's aesthetics score, utility flag, and feature print.
///
/// Everything runs on device with built-in models. If Vision fails (it can on the simulator), the
/// Vision fields stay nil and the pixel signals are still kept. Each Vision request fails on its own.
struct VisionImageAnalyzer: ImageAnalyzing {
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "index")
    private static let cost = AnalysisCost()

    func analyze(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> ImageSignals {
        let clock = ContinuousClock()
        let started = clock.now
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
        let printStarted = clock.now
        do {
            let observation = try await GenerateImageFeaturePrintRequest().perform(on: image, orientation: orientation)
            signals.featurePrint = FeaturePrint(observation)?.data
        } catch {
            Self.log.error("Feature print request failed: \(error)")
        }
        let ended = clock.now
        Self.cost.record(total: ended - started, print: ended - printStarted, printBytes: signals.featurePrint?.count)
        return signals
    }
}

/// Running averages of analysis time and stored print size, logged every `logEvery` photos, so the
/// feature print's cost on a large library can be read from the log.
private final class AnalysisCost: @unchecked Sendable {
    private static let logEvery = 100
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "index")

    private let lock = NSLock()
    private var count = 0
    private var prints = 0
    private var totalSeconds = 0.0
    private var printSeconds = 0.0
    private var printBytes = 0

    func record(total: Duration, print: Duration, printBytes bytes: Int?) {
        let line: String? = lock.withLock {
            count += 1
            totalSeconds += Self.seconds(total)
            printSeconds += Self.seconds(print)
            if let bytes {
                prints += 1
                printBytes += bytes
            }
            guard count.isMultiple(of: Self.logEvery) else { return nil }
            let n = Double(count)
            return String(
                format: "Analysis cost over %d photos: %.1f ms each, %.1f ms of it the feature print; %d prints stored, %d B each",
                count, totalSeconds / n * 1000, printSeconds / n * 1000, prints, prints == 0 ? 0 : printBytes / prints
            )
        }
        if let line { Self.log.info("\(line, privacy: .public)") }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
