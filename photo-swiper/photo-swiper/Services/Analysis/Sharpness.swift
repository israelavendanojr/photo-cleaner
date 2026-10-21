import Accelerate
import Foundation

/// How much fine detail a frame has: variance of the Laplacian, scored per tile.
///
/// Only the sharpest tile counts, so a portrait or bokeh shot with a crisp subject against a soft
/// background still reads as sharp. Values are on a 0–255 grayscale, so they're comparable across
/// images analyzed at the same `longEdge`.
enum Sharpness {
    /// Long edge the image is analyzed at. Changing it shifts every score, so bump `LibraryIndexer.featureVersion`.
    static let longEdge = 512
    /// Tiles per side.
    static let grid = 4

    private static let laplacian: [Float] = [
        0, 1, 0,
        1, -4, 1,
        0, 1, 0,
    ]

    /// The largest per-tile Laplacian variance.
    static func score(_ image: GrayscaleImage) -> Double {
        let width = image.width, height = image.height
        guard width >= 3, height >= 3 else { return 0 }

        var source = image.pixels.map(Float.init)
        var response = [Float](repeating: 0, count: width * height)
        let status = source.withUnsafeMutableBufferPointer { src in
            response.withUnsafeMutableBufferPointer { dst in
                var input = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(height),
                                          width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.stride)
                var output = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height),
                                           width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.stride)
                return vImageConvolve_PlanarF(&input, &output, nil, 0, 0, laplacian, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        guard status == kvImageNoError else { return 0 }

        let columns = min(grid, width), rows = min(grid, height)
        var best = 0.0
        response.withUnsafeBufferPointer { values in
            for tileY in 0..<rows {
                let y0 = tileY * height / rows, y1 = (tileY + 1) * height / rows
                for tileX in 0..<columns {
                    let x0 = tileX * width / columns, x1 = (tileX + 1) * width / columns
                    let count = Double((y1 - y0) * (x1 - x0))
                    var sum = 0.0, sumOfSquares = 0.0
                    for y in y0..<y1 {
                        let row = values.baseAddress! + y * width + x0
                        var rowSum: Float = 0, rowSquares: Float = 0
                        vDSP_sve(row, 1, &rowSum, vDSP_Length(x1 - x0))
                        vDSP_svesq(row, 1, &rowSquares, vDSP_Length(x1 - x0))
                        sum += Double(rowSum)
                        sumOfSquares += Double(rowSquares)
                    }
                    let mean = sum / count
                    best = max(best, sumOfSquares / count - mean * mean)
                }
            }
        }
        return best
    }
}
