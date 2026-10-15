import CoreGraphics
import Foundation

/// An 8-bit luminance bitmap, the input every pixel signal works on.
///
/// Made at a fixed long edge so scores don't depend on the source resolution. Images already smaller
/// than that are kept as they are, since upscaling would soften them.
struct GrayscaleImage: Sendable {
    let width: Int
    let height: Int
    /// Row-major, `width` bytes per row, 0 = black.
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "Expected \(width * height) pixels, got \(pixels.count)")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Draws `image` into a gray bitmap whose long edge is at most `longEdge`. Nil if it can't be drawn.
    init?(_ image: CGImage, longEdge: Int) {
        let scale = min(1, Double(longEdge) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }
}
