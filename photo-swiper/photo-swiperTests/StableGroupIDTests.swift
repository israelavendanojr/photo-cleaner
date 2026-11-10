import Foundation
import Testing
@testable import photo_swiper

/// Saved marks and drafts key on group ids, so the exact bytes must never change (JUN-45, Q-6).
/// These values were computed independently: SHA-256 over the sorted ids joined by newlines,
/// first 8 bytes in hex, after the prefix.
struct StableGroupIDTests {
    @Test func similarIDsAreExactlyWhatTheyWere() {
        #expect(SimilarGroup.stableID(for: ["B/L0/001", "A/L0/001", "C/L0/001"]) == "similar-8ae4764daee1fa10")
        #expect(SimilarGroup.stableID(for: ["x", "only/L0/001"]) == "similar-1c7d9643684f2e80")
    }

    @Test func duplicateIDsAreExactlyWhatTheyWere() {
        #expect(DuplicateGroup.stableID(for: ["A/L0/001", "B/L0/001"]) == "dup-5022385beceeeec9")
    }

    @Test func memberOrderDoesNotMatter() {
        #expect(stableGroupID(prefix: "p-", ids: ["c", "a", "b"]) == stableGroupID(prefix: "p-", ids: ["a", "b", "c"]))
    }
}
