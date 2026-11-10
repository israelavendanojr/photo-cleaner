import CoreGraphics
import Foundation
import ImageIO
import OSLog
import Synchronization
import Vision

/// Sharpness, exposure, and the duplicate hash from one grayscale bitmap, plus Vision's aesthetics score, utility flag, and feature print.
///
/// Everything runs on device with built-in models. If Vision fails (it can on the simulator), the
/// Vision fields stay nil and the pixel signals are still kept. Each Vision request fails on its own.
struct VisionImageAnalyzer: ImageAnalyzing {
    private static let log = Logger.app(category: "index")
    private static let cost = AnalysisCost()

    func analyze(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> ImageSignals {
        let clock = ContinuousClock()
        let started = clock.now
        var signals = ImageSignals()
        // Sharpness keeps the best tile and exposure is a histogram, so neither depends on orientation.
        if let gray = GrayscaleImage(image, longEdge: Sharpness.longEdge) {
            signals.sharpness = Sharpness.score(gray)
            signals.exposure = Exposure.stats(gray)
            signals.dHash = DHash.hash(gray, orientation: orientation)
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
private final class AnalysisCost: Sendable {
    private static let logEvery = 100
    private static let log = Logger.app(category: "index")

    private struct Totals {
        var count = 0
        var prints = 0
        var totalSeconds = 0.0
        var printSeconds = 0.0
        var printBytes = 0
    }

    private let totals = Mutex(Totals())

    func record(total: Duration, print: Duration, printBytes bytes: Int?) {
        let line: String? = totals.withLock { t in
            t.count += 1
            t.totalSeconds += Self.seconds(total)
            t.printSeconds += Self.seconds(print)
            if let bytes {
                t.prints += 1
                t.printBytes += bytes
            }
            guard t.count.isMultiple(of: Self.logEvery) else { return nil }
            let n = Double(t.count)
            return String(
                format: "Analysis cost over %d photos: %.1f ms each, %.1f ms of it the feature print; %d prints stored, %d B each",
                t.count, t.totalSeconds / n * 1000, t.printSeconds / n * 1000, t.prints, t.prints == 0 ? 0 : t.printBytes / t.prints
            )
        }
        if let line { Self.log.info("\(line, privacy: .public)") }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
