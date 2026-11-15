import CoreGraphics
import Foundation
import Testing
@testable import photo_swiper

/// Each edited video is exported once (JUN-50): a trim alone without re-encoding, any compression in
/// one re-encode with the trim applied while reading. `ExportPlan` is one step by construction, so a
/// video can't be encoded twice.
struct ExportPlanTests {
    private let source = VideoSourceInfo(naturalSize: CGSize(width: 3840, height: 2160), videoBitrate: 40_000_000,
                                         audioBitrate: 192_000, frameRate: 30, isHDR: false, color: nil)
    private let quarter = TrimRange(start: 0, end: 25)

    @Test func aTrimAloneIsCopiedWithoutReencoding() {
        let edit = PendingEdit(range: quarter, originalDuration: 100)
        #expect(ExportPlan.make(edit, source: source, levels: .standard) == .passthrough(quarter))
    }

    @Test(arguments: CompressionLevel.allCases)
    func compressionIsOneReencodeWithTheTrimApplied(_ level: CompressionLevel) {
        let settings = CompressionSettings.resolve(level, levels: .standard, source: source)
        let trimmed = PendingEdit(range: quarter, originalDuration: 100, compression: level)
        let whole = PendingEdit(originalDuration: 100, compression: level)

        #expect(ExportPlan.make(trimmed, source: source, levels: .standard) == .reencode(quarter, settings))
        #expect(ExportPlan.make(whole, source: source, levels: .standard) == .reencode(nil, settings))
    }

    @Test func anEmptyEditHasNothingToExport() {
        #expect(ExportPlan.make(PendingEdit(originalDuration: 100), source: source, levels: .standard) == nil)
    }

    @Test func theLoggedEstimateMatchesTheEdit() {
        let passthrough = ExportPlan.passthrough(quarter)
        #expect(passthrough.estimatedBytes(originalBytes: 400_000_000, originalDuration: 100) == 100_000_000)

        let settings = CompressionSettings.resolve(.balanced, levels: .standard, source: source)
        let reencode = ExportPlan.reencode(quarter, settings)
        #expect(reencode.estimatedBytes(originalBytes: 400_000_000, originalDuration: 100) == settings.estimatedBytes(seconds: 25))
    }
}
