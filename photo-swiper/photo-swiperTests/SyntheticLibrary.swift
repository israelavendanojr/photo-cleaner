import Foundation
@testable import photo_swiper

/// A made-up library shaped like a real one, for scaling and cache tests.
///
/// Photos come in outings: a few shots seconds apart (or minutes apart, so not neighbors), often of
/// the same scene. A few outings are bursts. Some photos are saved again later as near-exact copies.
/// Screenshots and videos are mixed in. Prints are made on demand from each photo's scene and
/// variant, so 50,000 of them never sit in memory at once. Seeded, so every run is the same.
struct SyntheticLibrary: Sendable {
    /// Newest first, as the library lists them.
    let candidates: [RankCandidate]
    let dimensions: Int
    private let seeds: [LibraryItem.ID: PrintSeed]

    private struct PrintSeed: Sendable {
        let scene: UInt64
        let variant: UInt64
        /// Nonzero for a later copy, which sits almost on top of its original.
        let copy: UInt64
    }

    init(count: Int, seed: UInt64 = 1, dimensions: Int = 768, start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        var rng = SplitMix64(seed: seed)
        var candidates: [RankCandidate] = []
        var seeds: [LibraryItem.ID: PrintSeed] = [:]
        candidates.reserveCapacity(count)
        var time = start
        var n = 0
        // About three years of photos.
        let outingGap = 3 * 365 * 86_400 / Double(max(count, 1)) * 4

        func photo(at date: Date, scene: UInt64, variant: UInt64, hashFlips: Int, burst: String? = nil,
                   copy: UInt64 = 0, sceneHash: UInt64, portrait: Bool, rng: inout SplitMix64) -> RankCandidate {
            n += 1
            let id = (copy == 0 ? "p" : "c") + String(n)
            seeds[id] = PrintSeed(scene: scene, variant: variant, copy: copy)
            var hash = sceneHash
            for _ in 0..<hashFlips { hash ^= 1 << (rng.next() % 64) }
            return RankCandidate(id: id, features: AssetFeatures(
                createdAt: date, bytes: Int64(1_000_000 + rng.next() % 4_000_000), isInBurst: burst != nil,
                burstID: burst, sharpness: Double(rng.next() % 1000) / 1000, isUtility: false,
                pixelWidth: portrait ? 3024 : 4032, pixelHeight: portrait ? 4032 : 3024, dHash: hash
            ))
        }

        var originals: [(RankCandidate, PrintSeed)] = []
        while candidates.count < count {
            time = time.addingTimeInterval(rng.exponential(mean: outingGap))
            let roll = rng.unit()
            if roll < 0.08 {
                n += 1
                candidates.append(RankCandidate(id: "s\(n)", features: AssetFeatures(
                    createdAt: time, bytes: 400_000, isScreenshot: true, isUtility: true, pixelWidth: 1179, pixelHeight: 2556
                )))
                continue
            }
            if roll < 0.12 {
                n += 1
                candidates.append(RankCandidate(id: "v\(n)", features: AssetFeatures(
                    createdAt: time, bytes: 40_000_000, isVideo: true, duration: 20
                )))
                continue
            }
            let portrait = rng.unit() < 0.5
            if roll < 0.14 {
                // A burst: 5–20 frames a tenth of a second apart, one scene.
                let scene = rng.next(), sceneHash = rng.next(), burst = "burst-\(scene)"
                for frame in 0..<(5 + Int(rng.next() % 16)) where candidates.count < count {
                    candidates.append(photo(at: time.addingTimeInterval(Double(frame) / 10), scene: scene, variant: rng.next(),
                                            hashFlips: 4 + Int(rng.next() % 5), burst: burst, sceneHash: sceneHash,
                                            portrait: portrait, rng: &rng))
                }
                continue
            }
            // An outing: mostly seconds apart, sometimes minutes, often the same scene again.
            let spaced = rng.unit() < 0.8 ? 3.0...60.0 : 120.0...1200.0
            var scene = rng.next(), sceneHash = rng.next()
            var shotTime = time
            for _ in 0..<(1 + rng.geometric(p: 0.25)) where candidates.count < count {
                if rng.unit() < 0.45 { scene = rng.next(); sceneHash = rng.next() }
                let shot = photo(at: shotTime, scene: scene, variant: rng.next(), hashFlips: 4 + Int(rng.next() % 5),
                                 sceneHash: sceneHash, portrait: portrait, rng: &rng)
                candidates.append(shot)
                if rng.unit() < 0.02, let printSeed = seeds[shot.id] { originals.append((shot, printSeed)) }
                shotTime = shotTime.addingTimeInterval(Double.random(in: spaced, using: &rng))
            }
            time = shotTime
        }

        // Copies saved later, any time after the original: same look, a hash bit or two off.
        for (original, printSeed) in originals {
            n += 1
            let id = "c\(n)"
            seeds[id] = PrintSeed(scene: printSeed.scene, variant: printSeed.variant, copy: rng.next() | 1)
            var features = original.features
            features.createdAt = original.features.createdAt.addingTimeInterval(rng.exponential(mean: 90 * 86_400))
            features.burstID = nil
            features.isInBurst = false
            var hash = features.dHash ?? 0
            for _ in 0..<Int(rng.next() % 3) { hash ^= 1 << (rng.next() % 64) }
            features.dHash = hash
            candidates.append(RankCandidate(id: id, features: features))
        }

        self.candidates = candidates.sorted { $0.features.createdAt > $1.features.createdAt }
        self.seeds = seeds
        self.dimensions = dimensions
    }

    /// The stored print for a photo; nil for screenshots and videos, which aren't analyzed here.
    func print(for id: LibraryItem.ID) -> FeaturePrint? {
        guard let seed = seeds[id] else { return nil }
        var scene = Self.unitVector(seed.scene, dimensions)
        let variant = Self.unitVector(seed.variant, dimensions)
        let copy = seed.copy == 0 ? nil : Self.unitVector(seed.copy, dimensions)
        // Shots of one scene sit about 0.25 apart; a copy about 0.01 from its original.
        for i in scene.indices { scene[i] += 0.18 * variant[i] + 0.007 * (copy?[i] ?? 0) }
        return FeaturePrint(vector: Self.normalized(scene))
    }

    func prints(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: FeaturePrint] {
        Dictionary(uniqueKeysWithValues: ids.compactMap { id in print(for: id).map { (id, $0) } })
    }

    private static func unitVector(_ seed: UInt64, _ dimensions: Int) -> [Float] {
        var rng = SplitMix64(seed: seed)
        return normalized((0..<dimensions).map { _ in Float(rng.gaussian()) })
    }

    private static func normalized(_ v: [Float]) -> [Float] {
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? v.map { $0 / norm } : v
    }
}

/// Small, fast, and seedable, so synthetic data is the same every run.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// In 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func exponential(mean: Double) -> Double { -mean * log(1 - unit()) }

    mutating func gaussian() -> Double {
        (-2 * log(1 - unit())).squareRoot() * cos(2 * .pi * unit())
    }

    /// Failures before the first success.
    mutating func geometric(p: Double) -> Int { Int(log(1 - unit()) / log(1 - p)) }
}
