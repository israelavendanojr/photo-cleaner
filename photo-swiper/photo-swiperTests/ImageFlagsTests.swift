import Foundation
import Testing
@testable import photo_swiper

private func analyzed(
    sharpness: Double? = 500,
    dark: Double = 0.05,
    bright: Double = 0.05,
    aesthetic: Double? = 0,
    utility: Bool? = false
) -> AssetFeatures {
    AssetFeatures(
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        bytes: 2_000_000,
        sharpness: sharpness,
        exposure: ExposureStats(mean: 0.5, darkFraction: dark, brightFraction: bright),
        aesthetic: aesthetic,
        isUtility: utility
    )
}

struct ImageFlagsTests {
    @Test func unanalyzedItemsGetNoFlags() {
        #expect(ImageFlags.classify(AssetFeatures(createdAt: .now, bytes: 1)).isEmpty)
    }

    @Test func anOrdinaryGoodPhotoGetsNoFlags() {
        #expect(ImageFlags.classify(analyzed()).isEmpty)
    }

    @Test func blurryJustBelowTheThreshold() {
        #expect(ImageFlags.classify(analyzed(sharpness: ImageFlags.blurryBelow - 0.1)) == [.blurry])
        #expect(ImageFlags.classify(analyzed(sharpness: ImageFlags.blurryBelow)).isEmpty)
    }

    @Test func aSoftPhotoVisionLikesIsNotBlurry() {
        let soft = ImageFlags.blurryBelow / 2
        #expect(ImageFlags.classify(analyzed(sharpness: soft, aesthetic: ImageFlags.intentionalSoftAbove + 0.01)).isEmpty)
        #expect(ImageFlags.classify(analyzed(sharpness: soft, aesthetic: ImageFlags.intentionalSoftAbove)) == [.blurry])
    }

    @Test func blurryNeedsAnalysis() {
        #expect(ImageFlags.classify(analyzed(sharpness: nil)).isEmpty)
    }

    @Test func utilityIsAReceipt() {
        #expect(ImageFlags.classify(analyzed(utility: true)) == [.receipt])
    }

    @Test func aBlurryReceiptShowsAsAReceiptSoItIsNotBlurredOnTheCard() {
        let flags = ImageFlags.classify(analyzed(sharpness: 5, utility: true))
        #expect(flags == [.receipt, .blurry])
        var item = PreviewSamples.plainPhoto
        item.flags = flags
        #expect(item.reviewFlag == .receipt)
    }

    @Test func mostlyBlackAndSoftIsAccidental() {
        let detail = ImageFlags.detailBelow
        #expect(ImageFlags.classify(analyzed(sharpness: detail - 1, dark: ImageFlags.mostlyDarkFraction)) == [.accidental])
        #expect(ImageFlags.classify(analyzed(sharpness: detail - 1, dark: ImageFlags.mostlyDarkFraction - 0.01)).isEmpty)
    }

    @Test func mostlyBlownAndSoftIsAccidental() {
        let detail = ImageFlags.detailBelow
        #expect(ImageFlags.classify(analyzed(sharpness: detail - 1, bright: ImageFlags.mostlyBrightFraction)) == [.accidental])
        #expect(ImageFlags.classify(analyzed(sharpness: detail - 1, bright: ImageFlags.mostlyBrightFraction - 0.01)).isEmpty)
    }

    @Test func aDarkNightShotWithDetailIsNotAccidental() {
        #expect(ImageFlags.classify(analyzed(sharpness: ImageFlags.detailBelow, dark: 0.97, aesthetic: -0.2)).isEmpty)
    }

    @Test func junkNeedsBothLowAestheticAndLowSharpness() {
        let junk = ImageFlags.junkAestheticBelow - 0.01
        #expect(ImageFlags.classify(analyzed(sharpness: ImageFlags.junkSharpnessBelow - 1, aesthetic: junk)) == [.accidental])
        #expect(ImageFlags.classify(analyzed(sharpness: ImageFlags.junkSharpnessBelow, aesthetic: junk)).isEmpty)
        #expect(ImageFlags.classify(analyzed(sharpness: ImageFlags.junkSharpnessBelow - 1, aesthetic: ImageFlags.junkAestheticBelow)).isEmpty)
    }

    @Test func accidentalReplacesBlurry() {
        let flags = ImageFlags.classify(analyzed(sharpness: 1, dark: 1))
        #expect(flags == [.accidental])
    }
}

struct AssetFeaturesCodingTests {
    @Test func featuresSavedBeforeImageSignalsStillDecode() throws {
        let old = #"{"createdAt":0,"bytes":42,"isVideo":false,"duration":0,"isScreenshot":true,"isFavorite":false,"isInBurst":false,"isBurstPick":false,"hasAdjustments":false}"#
        let features = try JSONDecoder().decode(AssetFeatures.self, from: Data(old.utf8))
        #expect(features.bytes == 42)
        #expect(features.isScreenshot)
        #expect(features.sharpness == nil && features.exposure == nil && features.aesthetic == nil && features.isUtility == nil)
    }

    @Test func savedItemsWithOldFeaturesStillDecode() throws {
        var item = PreviewSamples.plainPhoto
        item.features = AssetFeatures(createdAt: .now, bytes: 7)
        var json = try #require(String(data: JSONEncoder().encode(item), encoding: .utf8))
        // Saved before image signals existed: none of the new keys are present.
        #expect(!json.contains("sharpness"))
        json = json.replacingOccurrences(of: "\"bytes\":7", with: "\"bytes\":8")
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: Data(json.utf8))
        #expect(decoded.features?.bytes == 8)
    }

    @Test func imageSignalsRoundTrip() throws {
        let features = analyzed(aesthetic: 0.4, utility: true)
        #expect(try JSONDecoder().decode(AssetFeatures.self, from: JSONEncoder().encode(features)) == features)
    }
}
