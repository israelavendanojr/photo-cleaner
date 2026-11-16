import Testing
@testable import photo_swiper

/// The loose stack's angles come from card IDs, so they can't change between renders or launches.
struct StackPoseTests {
    @Test func aCardAlwaysLiesTheSameWay() {
        #expect(StackPose.tilt(for: "photo-12") == StackPose.tilt(for: "photo-12"))
    }

    /// Pinned values: a per-launch seed (as `Hasher` has) would break these on the next run.
    @Test func theHashIsTheSameOnEveryLaunch() {
        #expect(StackPose.stableHash("") == 0xCBF2_9CE4_8422_2325)
        #expect(StackPose.stableHash("a") == 0xAF63_DC4C_8601_EC8C)
    }

    @Test func everyTiltIsAFewDegreesEitherWay() {
        let tilts = (0..<500).map { StackPose.tilt(for: "card-\($0)") }
        for tilt in tilts {
            #expect(DS.Stack.tilt.contains(abs(tilt)))
        }
        #expect(tilts.contains { $0 > 0 })
        #expect(tilts.contains { $0 < 0 })
    }
}
