import Accelerate
import Foundation

/// Luminance histogram stats: how bright a frame is on average, and how much of it is crushed or blown.
enum Exposure {
    /// Pixels at or below this count as nearly black.
    static let nearBlack: UInt8 = 15
    /// Pixels at or above this count as nearly white.
    static let nearWhite: UInt8 = 240

    static func stats(_ image: GrayscaleImage) -> ExposureStats {
        var histogram = [vImagePixelCount](repeating: 0, count: 256)
        var pixels = image.pixels
        let status = pixels.withUnsafeMutableBytes { bytes in
            histogram.withUnsafeMutableBufferPointer { bins in
                var buffer = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(image.height),
                                           width: vImagePixelCount(image.width), rowBytes: image.width)
                return vImageHistogramCalculation_Planar8(&buffer, bins.baseAddress!, vImage_Flags(kvImageNoFlags))
            }
        }
        let total = Double(image.width * image.height)
        guard status == kvImageNoError, total > 0 else { return ExposureStats(mean: 0, darkFraction: 0, brightFraction: 0) }

        var weighted = 0.0
        for (level, count) in histogram.enumerated() { weighted += Double(level) * Double(count) }
        let dark = histogram[...Int(nearBlack)].reduce(0, +)
        let bright = histogram[Int(nearWhite)...].reduce(0, +)
        return ExposureStats(
            mean: weighted / total / 255,
            darkFraction: Double(dark) / total,
            brightFraction: Double(bright) / total
        )
    }
}
