import XCTest
@testable import photo_swiper

/// Fails a Release test run while launch links are still unset. Debug runs skip it, so day-to-day
/// testing stays green. Running it in Release needs `ENABLE_TESTABILITY=YES` for `@testable import`.
final class LaunchGuardTests: XCTestCase {
    func testLaunchURLsAreSet() throws {
        #if DEBUG
        throw XCTSkip("Launch links are checked against a Release configuration only.")
        #else
        XCTAssertEqual(AppInfo.missingLaunchValues, [], "Set these in AppInfo before shipping")
        #endif
    }
}
