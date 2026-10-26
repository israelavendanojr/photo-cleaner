import Accelerate
import Foundation
import Vision

/// Vision's image feature print as a plain vector, so it can be stored and compared without Vision.
///
/// `FeaturePrintObservation` has no public initializer from stored bytes, so the index keeps the raw
/// Float32 vector and distances are computed here. For revision 2 that's the same Euclidean distance
/// `FeaturePrintObservation.distance(to:)` returns; a test pins that.
struct FeaturePrint: Hashable, Sendable {
    let vector: [Float]

    init(vector: [Float]) {
        self.vector = vector
    }

    /// From stored bytes: native-endian Float32s. Nil when empty or not a whole number of floats.
    init?(data: Data) {
        let size = MemoryLayout<Float>.size
        guard !data.isEmpty, data.count.isMultiple(of: size) else { return nil }
        var vector = [Float](repeating: 0, count: data.count / size)
        _ = vector.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        self.vector = vector
    }

    init?(_ observation: FeaturePrintObservation) {
        switch observation.elementType {
        case .float:
            self.init(data: observation.data)
        case .double:
            let size = MemoryLayout<Double>.size
            guard !observation.data.isEmpty, observation.data.count.isMultiple(of: size) else { return nil }
            var doubles = [Double](repeating: 0, count: observation.data.count / size)
            _ = doubles.withUnsafeMutableBytes { observation.data.copyBytes(to: $0) }
            self.init(vector: doubles.map(Float.init))
        @unknown default:
            return nil
        }
    }

    /// What the index stores.
    var data: Data {
        vector.withUnsafeBytes { Data($0) }
    }

    /// Euclidean distance. Prints of different lengths (different revisions) never match.
    static func euclidean(_ a: FeaturePrint, _ b: FeaturePrint) -> Float {
        guard a.vector.count == b.vector.count, !a.vector.isEmpty else { return .infinity }
        return vDSP.distanceSquared(a.vector, b.vector).squareRoot()
    }
}
