import Foundation
import Testing
@testable import photo_swiper

/// The "Contact support" email.
struct SupportMailTests {
    private let url = SupportMail.url(
        email: "help@example.com", appName: "Sample App", version: "1.2", build: "34",
        systemVersion: "18.4", model: "iPhone17,3"
    )

    private func query(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    @Test func addressesSupport() throws {
        let url = try #require(url)
        #expect(url.scheme == "mailto")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == "help@example.com")
    }

    @Test func subjectNamesTheApp() {
        #expect(query("subject") == "Sample App support")
    }

    @Test func bodyFooterHasVersionBuildSystemAndDevice() throws {
        let body = try #require(query("body"))
        #expect(body.contains("Sample App 1.2 (build 34)"))
        #expect(body.contains("iOS 18.4"))
        #expect(body.contains("iPhone17,3"))
        // The details sit under room to write.
        #expect(body.hasPrefix("\n\n"))
    }

    @Test func spacesAndNewlinesArePercentEncoded() throws {
        let string = try #require(url?.absoluteString)
        #expect(!string.contains(" "))
        #expect(!string.contains("\n"))
        #expect(string.contains("subject=Sample%20App%20support"))
    }
}
