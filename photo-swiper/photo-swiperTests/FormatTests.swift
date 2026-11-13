import Foundation
import Testing
@testable import photo_swiper

/// Sizes and times as every screen shows them.
struct FormatTests {
    @Test(arguments: [
        (Int64(0), "0 MB"), (100_000, "0.1 MB"), (3_400_000, "3.4 MB"), (38_000_000, "38 MB"),
        (1_230_000_000, "1.23 GB"), (1_200_000_000, "1.2 GB"),
    ])
    func sizesUseDecimalUnitsFromMegabytesUp(bytes: Int64, expected: String) {
        #expect(Format.size(bytes) == expected)
    }

    @Test func fractionsReadAsWholePercents() {
        #expect(Format.percent(0.21) == "21%")
        #expect(Format.percent(0.996) == "100%")
        #expect(Format.percent(0) == "0%")
    }

    @Test func aPercentChangeHasASignAndOneDecimal() {
        #expect(Format.signedPercent(0.345) == "+34.5%")
        #expect(Format.signedPercent(-0.25) == "−25.0%")
        #expect(Format.signedPercent(0) == "+0.0%")
        #expect(Format.signedPercent(0.12345) == "+12.3%")
        #expect(Format.signedPercent(-1) == "−100.0%")
    }

    @Test func theWeeklyChangeReadsAgainstLastWeekOrOnItsOwn() {
        let up = DashboardSnapshot.WeeklyChange(delta: 1_200_000_000, percent: 0.345)
        #expect(Format.weeklyChange(up) == "+1.2 GB (+34.5%) vs last week")
        let down = DashboardSnapshot.WeeklyChange(delta: -400_000_000, percent: -0.25)
        #expect(Format.weeklyChange(down) == "−400 MB (−25.0%) vs last week")
        let fresh = DashboardSnapshot.WeeklyChange(delta: 1_200_000_000, percent: nil)
        #expect(Format.weeklyChange(fresh) == "+1.2 GB this week")
    }

    @Test func aChangeHasASign() {
        #expect(Format.signedSize(1_200_000_000) == "+1.2 GB")
        #expect(Format.signedSize(-340_000_000) == "−340 MB")
    }
}
