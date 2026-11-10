import Foundation
import Testing
@testable import photo_swiper

/// The last step before a real delete: how a request's items are sorted before the system prompt
/// (JUN-45, Q-4). Limited access is handled after, by `FeedViewModel` (see `LimitedAccessTests`).
struct DeletionOutcomeTests {
    @Test func missingUndeletableAndDeletableAreSortedOut() {
        let outcome = DeletionOutcome.make(requested: ["a", "b", "c", "d", "e"], found: ["a", "c", "d", "e"], deletable: ["a", "e"])
        #expect(outcome.missing == ["b"])
        #expect(outcome.undeletable == ["c", "d"])
        #expect(outcome.deleted.isEmpty, "Nothing counts as deleted before the user confirms")
    }

    @Test func everythingFoundAndDeletableReportsNothing() {
        let outcome = DeletionOutcome.make(requested: ["a", "b"], found: ["b", "a"], deletable: ["a", "b"])
        #expect(outcome.missing.isEmpty && outcome.undeletable.isEmpty && outcome.deleted.isEmpty)
    }

    @Test func nothingFoundIsAllMissing() {
        let outcome = DeletionOutcome.make(requested: ["a", "b"], found: [], deletable: [])
        #expect(outcome.missing == ["a", "b"])
        #expect(outcome.undeletable.isEmpty)
    }

    @Test func anEmptyRequestReportsNothing() {
        let outcome = DeletionOutcome.make(requested: [], found: [], deletable: [])
        #expect(outcome.missing.isEmpty && outcome.undeletable.isEmpty && outcome.deleted.isEmpty)
    }

    @Test func orderFollowsTheRequestAndTheLibrary() {
        let outcome = DeletionOutcome.make(requested: ["z", "y", "x", "w"], found: ["w", "x"], deletable: [])
        #expect(outcome.missing == ["z", "y"])
        #expect(outcome.undeletable == ["w", "x"])
    }
}
