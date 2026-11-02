import CoreGraphics
import Foundation
import ImageIO

/// A 64-bit difference hash: the upright image averaged down to a 9×8 grid, one bit per pair of
/// horizontal neighbors saying whether brightness rises left to right.
///
/// It depends only on coarse structure, so a recompressed, resized, or re-downloaded copy of a photo
/// hashes the same or within a few bits, while different photos land about 32 bits apart. Computed
/// in the upright orientation, so a copy saved with its rotation baked in matches one that only
/// carries the orientation flag.
enum DHash {
    /// Bump when the hash changes; the indexer rehashes every older record.
    static let version = 1
    private static let columns = 9
    private static let rows = 8

    /// From a decoded image, at the same size `VisionImageAnalyzer` analyzes, so both paths agree.
    static func compute(_ image: CGImage, orientation: CGImagePropertyOrientation) -> UInt64? {
        GrayscaleImage(image, longEdge: Sharpness.longEdge).map { hash($0, orientation: orientation) }
    }

    /// `gray` holds the image as stored; `orientation` says how to show it upright.
    static func hash(_ gray: GrayscaleImage, orientation: CGImagePropertyOrientation = .up) -> UInt64 {
        let w = gray.width, h = gray.height
        let swapped: Bool, flipX: Bool, flipY: Bool
        switch orientation {
        case .up: (swapped, flipX, flipY) = (false, false, false)
        case .upMirrored: (swapped, flipX, flipY) = (false, true, false)
        case .down: (swapped, flipX, flipY) = (false, true, true)
        case .downMirrored: (swapped, flipX, flipY) = (false, false, true)
        // Rotated: the stored rows become upright columns. `flipX` mirrors the upright x (from the
        // stored y), `flipY` the upright y (from the stored x).
        case .leftMirrored: (swapped, flipX, flipY) = (true, false, false)
        case .right: (swapped, flipX, flipY) = (true, true, false)
        case .rightMirrored: (swapped, flipX, flipY) = (true, true, true)
        case .left: (swapped, flipX, flipY) = (true, false, true)
        @unknown default: (swapped, flipX, flipY) = (false, false, false)
        }

        // Upright column and row of every stored x and y.
        func bins(count: Int, length: Int, flip: Bool) -> [Int] {
            (0..<length).map { i in
                let upright = flip ? length - 1 - i : i
                return min(count - 1, upright * count / max(length, 1))
            }
        }
        let binOfX, binOfY: [Int]
        if swapped {
            binOfX = bins(count: rows, length: w, flip: flipY)
            binOfY = bins(count: columns, length: h, flip: flipX)
        } else {
            binOfX = bins(count: columns, length: w, flip: flipX)
            binOfY = bins(count: rows, length: h, flip: flipY)
        }

        var sums = [Int](repeating: 0, count: columns * rows)
        var counts = [Int](repeating: 0, count: columns * rows)
        gray.pixels.withUnsafeBufferPointer { pixels in
            for y in 0..<h {
                let by = binOfY[y], rowStart = y * w
                for x in 0..<w {
                    let bx = binOfX[x]
                    let cell = swapped ? bx * columns + by : by * columns + bx
                    sums[cell] += Int(pixels[rowStart + x])
                    counts[cell] += 1
                }
            }
        }
        let means = zip(sums, counts).map { $1 == 0 ? 0.0 : Double($0) / Double($1) }

        var hash: UInt64 = 0
        for row in 0..<rows {
            for column in 0..<(columns - 1) {
                hash <<= 1
                if means[row * columns + column] < means[row * columns + column + 1] { hash |= 1 }
            }
        }
        return hash
    }

    /// Bits that differ.
    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
