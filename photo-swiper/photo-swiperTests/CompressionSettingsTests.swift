import CoreGraphics
import Foundation
import Testing
@testable import photo_swiper

/// The compression levels' rules (JUN-50): never above the source's resolution or bitrate, the aspect
/// ratio and HDR kept, and a level that saves under 10% offered as "Already small".
struct CompressionSettingsTests {
    private func source(_ width: CGFloat, _ height: CGFloat, video: Int = 20_000_000, audio: Int? = 192_000,
                        isHDR: Bool = false, color: VideoColor? = nil) -> VideoSourceInfo {
        VideoSourceInfo(naturalSize: CGSize(width: width, height: height), videoBitrate: video, audioBitrate: audio,
                        frameRate: 30, isHDR: isHDR, color: color)
    }

    private func resolve(_ level: CompressionLevel, _ source: VideoSourceInfo) -> CompressionSettings {
        CompressionSettings.resolve(level, levels: .standard, source: source)
    }

    // MARK: Resolution

    @Test func theLongEdgeComesDownToTheLevelsKeepingTheAspectRatio() {
        let fourK = source(3840, 2160)
        #expect((resolve(.light, fourK).width, resolve(.light, fourK).height) == (3840, 2160), "Light keeps the source's size")
        #expect((resolve(.balanced, fourK).width, resolve(.balanced, fourK).height) == (1920, 1080))
        #expect((resolve(.max, fourK).width, resolve(.max, fourK).height) == (1280, 720))
    }

    @Test func aPortraitVideoIsMeasuredByItsLongEdge() {
        let portrait = source(2160, 3840)
        #expect((resolve(.max, portrait).width, resolve(.max, portrait).height) == (720, 1280))
    }

    @Test func neverAboveTheSourcesResolution() {
        let small = source(1280, 720)
        for level in CompressionLevel.allCases {
            #expect((resolve(level, small).width, resolve(level, small).height) == (1280, 720))
        }
    }

    @Test func sizesAreEvenForTheEncoder() {
        let odd = source(1918, 1081)
        let settings = resolve(.max, odd)
        #expect(settings.width.isMultiple(of: 2) && settings.height.isMultiple(of: 2))
        #expect(settings.width == 1280)
    }

    // MARK: Bitrate

    @Test func neverAboveTheSourcesBitrate() {
        let lowBitrate = source(3840, 2160, video: 4_000_000)
        #expect(resolve(.light, lowBitrate).videoBitrate == 2_400_000, "Light is 60% of the source")
        #expect(resolve(.balanced, lowBitrate).videoBitrate == 4_000_000, "6 Mbps would be above the source's 4")
        #expect(resolve(.max, lowBitrate).videoBitrate == 2_500_000)

        let tiny = source(1280, 720, video: 1_000_000)
        #expect(resolve(.max, tiny).videoBitrate == 1_000_000)
    }

    @Test func audioIs128kOrTheSourcesIfLower() {
        #expect(resolve(.balanced, source(1920, 1080, audio: 256_000)).audioBitrate == 128_000)
        #expect(resolve(.balanced, source(1920, 1080, audio: 96_000)).audioBitrate == 96_000)
        #expect(resolve(.balanced, source(1920, 1080, audio: 0)).audioBitrate == 128_000, "A track that doesn't say gets the level's")
        #expect(resolve(.balanced, source(1920, 1080, audio: nil)).audioBitrate == nil, "No sound, no audio track")
    }

    // MARK: HDR

    @Test func hdrStaysHDRWithItsColorTags() {
        let hlg = VideoColor(primaries: "ITU_R_2020", transferFunction: "ITU_R_2100_HLG", matrix: "ITU_R_2020")
        let settings = resolve(.max, source(3840, 2160, isHDR: true, color: hlg))
        #expect(settings.isHDR)
        #expect(settings.color == hlg)
        #expect(!resolve(.max, source(3840, 2160)).isHDR)
    }

    // MARK: Estimate

    @Test func theEstimateIsBothBitratesTimesTheKeptLength() {
        let settings = resolve(.balanced, source(3840, 2160))
        // (6,000,000 + 128,000) bits/s × 10 s ÷ 8
        #expect(settings.estimatedBytes(seconds: 10) == 7_660_000)
    }

    @Test func theEstimateTakesTheTrimIntoAccount() {
        let fourK = source(3840, 2160)
        let whole = PendingEdit(originalDuration: 100)
        let quarter = PendingEdit(range: TrimRange(start: 0, end: 25), originalDuration: 100)
        let full = CompressionEstimate.make(.balanced, levels: .standard, source: fourK, originalBytes: 500_000_000, edit: whole)
        let trimmed = CompressionEstimate.make(.balanced, levels: .standard, source: fourK, originalBytes: 500_000_000, edit: quarter)

        #expect(full.trimmedBytes == 500_000_000)
        #expect(trimmed.trimmedBytes == 125_000_000)
        #expect(trimmed.compressedBytes == full.compressedBytes / 4)
    }

    // MARK: Already small

    @Test func aLevelThatSavesUnderTenPercentIsAlreadySmall() {
        // 10 s at about 2.2 Mbps in all: Max (2.5 Mbps, capped to the source's 2) saves almost nothing.
        let small = source(1280, 720, video: 2_000_000, audio: 128_000)
        let edit = PendingEdit(originalDuration: 10)
        let bytes: Int64 = 2_700_000
        #expect(CompressionEstimate.make(.max, levels: .standard, source: small, originalBytes: bytes, edit: edit).isAlreadySmall)
        #expect(!CompressionEstimate.make(.light, levels: .standard, source: small, originalBytes: bytes, edit: edit).isAlreadySmall,
                "Light still saves 40% of the video")

        let big = source(3840, 2160, video: 40_000_000)
        #expect(!CompressionEstimate.make(.max, levels: .standard, source: big, originalBytes: 50_000_000, edit: edit).isAlreadySmall)
    }

    @Test func anEstimateIsNeverLargerThanTheVideoAfterTrimming() {
        let small = source(1280, 720, video: 2_000_000)
        let estimate = CompressionEstimate.make(.balanced, levels: .standard, source: small, originalBytes: 1_000_000,
                                                edit: PendingEdit(originalDuration: 10))
        #expect(estimate.compressedBytes == 1_000_000)
        #expect(estimate.isAlreadySmall)
    }
}
