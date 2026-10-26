import CoreGraphics
import Foundation
import Testing
import Vision
@testable import photo_swiper

/// Synthetic grayscale images for signal tests.
enum TestImages {
    static func filled(_ value: UInt8, width: Int = 128, height: Int = 128) -> GrayscaleImage {
        GrayscaleImage(width: width, height: height, pixels: [UInt8](repeating: value, count: width * height))
    }

    static func checkerboard(width: Int = 256, height: Int = 256, square: Int = 4) -> GrayscaleImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width where (x / square + y / square).isMultiple(of: 2) {
                pixels[y * width + x] = 255
            }
        }
        return GrayscaleImage(width: width, height: height, pixels: pixels)
    }

    /// Three passes of a box blur, close to a Gaussian.
    static func blurred(_ image: GrayscaleImage, radius: Int = 4) -> GrayscaleImage {
        var pixels = image.pixels.map(Double.init)
        let w = image.width, h = image.height
        for _ in 0..<3 {
            var next = pixels
            for y in 0..<h {
                for x in 0..<w {
                    var sum = 0.0, count = 0.0
                    for dy in -radius...radius {
                        for dx in -radius...radius {
                            let sx = min(max(x + dx, 0), w - 1), sy = min(max(y + dy, 0), h - 1)
                            sum += pixels[sy * w + sx]
                            count += 1
                        }
                    }
                    next[y * w + x] = sum / count
                }
            }
            pixels = next
        }
        return GrayscaleImage(width: w, height: h, pixels: pixels.map { UInt8(min(max($0.rounded(), 0), 255)) })
    }

    /// Copies `patch` into `image` with its top-left corner at (x, y).
    static func pasting(_ patch: GrayscaleImage, into image: GrayscaleImage, x: Int, y: Int) -> GrayscaleImage {
        var pixels = image.pixels
        for row in 0..<patch.height {
            for column in 0..<patch.width {
                pixels[(y + row) * image.width + x + column] = patch.pixels[row * patch.width + column]
            }
        }
        return GrayscaleImage(width: image.width, height: image.height, pixels: pixels)
    }

    /// A smooth left-to-right ramp: no edges anywhere.
    static func gradient(width: Int = 256, height: Int = 256) -> GrayscaleImage {
        let pixels = (0..<height).flatMap { _ in (0..<width).map { UInt8($0 * 255 / max(width - 1, 1)) } }
        return GrayscaleImage(width: width, height: height, pixels: pixels)
    }
}

struct SharpnessTests {
    @Test func checkerboardIsSharperThanItsBlurredCopy() {
        let sharp = Sharpness.score(TestImages.checkerboard())
        let soft = Sharpness.score(TestImages.blurred(TestImages.checkerboard()))
        #expect(sharp > ImageFlags.blurryBelow)
        #expect(soft < ImageFlags.blurryBelow)
        #expect(sharp > soft * 10)
    }

    @Test func aSharpSubjectOnABlurredBackgroundStaysSharp() {
        let background = TestImages.blurred(TestImages.checkerboard())
        let subject = TestImages.checkerboard(width: 64, height: 64)
        let portrait = TestImages.pasting(subject, into: background, x: 96, y: 96)
        #expect(Sharpness.score(background) < ImageFlags.blurryBelow)
        #expect(Sharpness.score(portrait) > ImageFlags.blurryBelow)
    }

    @Test func flatAndSmoothImagesHaveNoDetail() {
        #expect(Sharpness.score(TestImages.filled(128)) == 0)
        #expect(Sharpness.score(TestImages.gradient()) < 1)
    }

    @Test func tinyImagesScoreZeroInsteadOfCrashing() {
        #expect(Sharpness.score(TestImages.filled(10, width: 2, height: 2)) == 0)
    }

    @Test func largeImagesAreDownscaledToTheLongEdge() throws {
        let context = try #require(CGContext(
            data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        let source = try #require(context.makeImage())
        let image = try #require(GrayscaleImage(source, longEdge: Sharpness.longEdge))
        #expect(image.width == 512)
        #expect(image.height == 256)
        #expect(image.pixels.allSatisfy { $0 == 255 })
    }
}

struct ExposureTests {
    @Test func allBlackIsAllDark() {
        let stats = Exposure.stats(TestImages.filled(0))
        #expect(stats.mean == 0)
        #expect(stats.darkFraction == 1)
        #expect(stats.brightFraction == 0)
    }

    @Test func allWhiteIsAllBright() {
        let stats = Exposure.stats(TestImages.filled(255))
        #expect(stats.mean == 1)
        #expect(stats.darkFraction == 0)
        #expect(stats.brightFraction == 1)
    }

    @Test func midGrayIsNeither() {
        let stats = Exposure.stats(TestImages.filled(128))
        #expect(abs(stats.mean - 128.0 / 255) < 1e-9)
        #expect(stats.darkFraction == 0)
        #expect(stats.brightFraction == 0)
    }

    @Test func fractionsCountOnlyTheirPixels() {
        let half = GrayscaleImage(width: 4, height: 1, pixels: [0, Exposure.nearBlack, 128, Exposure.nearWhite])
        let stats = Exposure.stats(half)
        #expect(stats.darkFraction == 0.5)
        #expect(stats.brightFraction == 0.25)
    }
}

struct NightShotSignalTests {
    /// Mostly black with a few sharp lights, like a city at night.
    @Test func aDarkFrameWithLightsIsNotAccidental() {
        var night = TestImages.filled(4, width: 256, height: 256)
        for (x, y) in [(20, 30), (80, 40), (150, 200), (220, 90), (60, 180), (200, 220)] {
            night = TestImages.pasting(TestImages.filled(255, width: 4, height: 4), into: night, x: x, y: y)
        }
        let exposure = Exposure.stats(night)
        let features = AssetFeatures(createdAt: .now, bytes: 1, sharpness: Sharpness.score(night), exposure: exposure)
        #expect(exposure.darkFraction >= ImageFlags.mostlyDarkFraction)
        #expect(!ImageFlags.isAccidental(features))
        #expect(ImageFlags.classify(features).isEmpty)
    }

    @Test func aPocketShotIsAccidental() {
        let pocket = TestImages.blurred(TestImages.filled(3, width: 128, height: 128))
        let features = AssetFeatures(createdAt: .now, bytes: 1, sharpness: Sharpness.score(pocket), exposure: Exposure.stats(pocket))
        #expect(ImageFlags.classify(features) == [.accidental])
    }
}

struct FeaturePrintTests {
    @Test func bytesRoundTrip() throws {
        let print = FeaturePrint(vector: [0, 1.5, -2, .ulpOfOne])
        #expect(FeaturePrint(data: print.data) == print)
        #expect(FeaturePrint(data: Data()) == nil)
        #expect(FeaturePrint(data: Data([1, 2, 3])) == nil)
    }

    @Test func euclideanDistance() {
        #expect(FeaturePrint.euclidean(FeaturePrint(vector: [0, 0]), FeaturePrint(vector: [3, 4])) == 5)
        #expect(FeaturePrint.euclidean(FeaturePrint(vector: [1, 2]), FeaturePrint(vector: [1, 2])) == 0)
        #expect(FeaturePrint.euclidean(FeaturePrint(vector: [1]), FeaturePrint(vector: [1, 2])) == .infinity)
    }

    /// The stored vector compares the way Vision does. Vision may not run on the simulator; the test
    /// then has nothing to check and passes.
    @Test func distanceMatchesVision() async throws {
        let a = try image(stripes: 8), b = try image(stripes: 9)
        let printA: FeaturePrintObservation, printB: FeaturePrintObservation
        do {
            printA = try await GenerateImageFeaturePrintRequest().perform(on: a)
            printB = try await GenerateImageFeaturePrintRequest().perform(on: b)
        } catch {
            return
        }
        let ours = FeaturePrint.euclidean(try #require(FeaturePrint(printA)), try #require(FeaturePrint(printB)))
        #expect(abs(Double(ours) - (try printA.distance(to: printB))) < 1e-3)
    }

    private func image(stripes: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.9, green: 0.7, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        context.setFillColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1)
        for i in 0..<stripes where i.isMultiple(of: 2) {
            context.fill(CGRect(x: i * 256 / stripes, y: 0, width: 256 / stripes, height: 256))
        }
        return try #require(context.makeImage())
    }
}
