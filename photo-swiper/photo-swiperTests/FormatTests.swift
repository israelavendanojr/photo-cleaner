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

    @Test func aChangeHasASign() {
        #expect(Format.signedSize(1_200_000_000) == "+1.2 GB")
        #expect(Format.signedSize(-340_000_000) == "−340 MB")
    }

    @Test func underAMinuteIsJustNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Format.relative(now.addingTimeInterval(-20), now: now) == "just now")
        #expect(Format.relative(now.addingTimeInterval(-600), now: now) != "just now")
    }
}
