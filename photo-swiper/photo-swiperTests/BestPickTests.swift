import Foundation
import Testing
@testable import photo_swiper

struct BestPickTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// A well-exposed, average frame unless told otherwise. Later ids are newer.
    private func frame(
        _ id: String, sharpness: Double? = 200, dark: Double = 0, aesthetic: Double? = 0,
        favorite: Bool = false, userPick: Bool = false, autoPick: Bool = false, edited: Bool = false
    ) -> RankCandidate {
        RankCandidate(id: id, features: AssetFeatures(
            createdAt: base.addingTimeInterval(Double(id.unicodeScalars.last!.value)), bytes: 3_000_000,
            isFavorite: favorite, isInBurst: userPick || autoPick, isBurstPick: userPick || autoPick,
            isUserBurstPick: userPick ? true : nil, hasAdjustments: edited, sharpness: sharpness,
            exposure: ExposureStats(mean: 0.45, darkFraction: dark, brightFraction: 0), aesthetic: aesthetic
        ))
    }

    private func choose(_ members: [RankCandidate]) -> BestPick.Choice? {
        BestPick.choose(members)
    }

    @Test func aFavoriteWinsEvenOverASharperFrame() {
        let choice = choose([frame("a", sharpness: 900), frame("b", favorite: true), frame("c", userPick: true, edited: true)])
        #expect(choice == BestPick.Choice(bestID: "b", reason: .favorite))
    }

    @Test func twoFavoritesMeanNoGroup() {
        #expect(choose([frame("a", favorite: true), frame("b", favorite: true), frame("c")]) == nil)
    }

    @Test func theUsersBurstPickWins() {
        let choice = choose([frame("a", sharpness: 900), frame("b", userPick: true), frame("c", edited: true)])
        #expect(choice == BestPick.Choice(bestID: "b", reason: .burstPick))
    }

    @Test func theCamerasAutoPickIsNotCalledYours() {
        let choice = choose([frame("a", sharpness: 900), frame("b", autoPick: true)])
        #expect(choice == BestPick.Choice(bestID: "a", reason: .sharpest))
    }

    @Test func theEditedFrameWins() {
        let choice = choose([frame("a", sharpness: 900), frame("b", edited: true)])
        #expect(choice == BestPick.Choice(bestID: "b", reason: .edited))
    }

    @Test func anEarlierSignalSharedByTwoPassesToTheNext() {
        // Both are user picks; only one is edited.
        let choice = choose([frame("a", userPick: true), frame("b", userPick: true, edited: true), frame("c", edited: true)])
        #expect(choice == BestPick.Choice(bestID: "b", reason: .edited))
    }

    @Test func theSharpestFrameWins() {
        let choice = choose([frame("a", sharpness: 40), frame("b", sharpness: 600), frame("c", sharpness: 300)])
        #expect(choice == BestPick.Choice(bestID: "b", reason: .sharpest))
    }

    @Test func theBestExposedFrameWins() {
        let choice = choose([frame("a", dark: 0.6), frame("b"), frame("c", dark: 0.3)])
        #expect(choice == BestPick.Choice(bestID: "b", reason: .exposure))
    }

    @Test func theHighestRatedFrameWins() {
        let choice = choose([frame("a", aesthetic: -0.2), frame("b", aesthetic: 0.6), frame("c", aesthetic: 0.1)])
        #expect(choice == BestPick.Choice(bestID: "b", reason: .aesthetic))
    }

    @Test func winningOnTheMixWithoutToppingAnySignalSaysSo() {
        // w scales to 0.9 on every signal; x tops sharpness, y tops exposure and aesthetics.
        let w = frame("w", sharpness: 637, dark: 0.1, aesthetic: 0.8)
        let x = frame("x", sharpness: 1_000, dark: 1, aesthetic: -1)
        let y = frame("y", sharpness: 10, dark: 0, aesthetic: 1)
        #expect(choose([w, x, y]) == BestPick.Choice(bestID: "w", reason: .overall))
    }

    @Test func aSignalOneFrameLacksIsIgnored() {
        // Without b's aesthetics score, a's higher score can't be claimed; sharpness decides.
        let choice = choose([frame("a", sharpness: 100, aesthetic: 0.9), frame("b", sharpness: 300, aesthetic: nil)])
        #expect(choice == BestPick.Choice(bestID: "b", reason: .sharpest))
    }

    @Test func identicalFramesPickTheNewestWithoutClaimingWhy() {
        #expect(choose([frame("a"), frame("b")]) == BestPick.Choice(bestID: "b", reason: .overall))
    }

    @Test func noReasonClaimsWhatIsNotMeasured() {
        let claims = BestPick.Reason.allCases.map(\.rawValue).joined(separator: " ").lowercased()
        #expect(!claims.contains("eye"))
        #expect(!claims.contains("blink"))
        #expect(!claims.contains("smil"))
    }
}
