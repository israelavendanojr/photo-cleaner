import Testing
@testable import photo_swiper

/// The trim handles against what's saved: when leaving the viewer asks first (JUN-7).
@MainActor
struct TrimDraftTests {
    @Test func nothingChangedLeavesWithoutAsking() {
        let draft = TrimDraft(duration: 100)
        #expect(!draft.isTrimmed)
        #expect(!draft.hasUnsavedChanges)
        #expect(draft.result == nil)
    }

    @Test func movingAHandleAsksBeforeLeaving() {
        var start = TrimDraft(duration: 100)
        start.setStart(10)
        #expect(start.isTrimmed)
        #expect(start.hasUnsavedChanges)
        #expect(start.result == PendingEdit(range: TrimRange(start: 10, end: 100), originalDuration: 100))

        var end = TrimDraft(duration: 100)
        end.setEnd(60)
        #expect(end.hasUnsavedChanges)
    }

    @Test func movingAHandleBackToTheEndIsNoChange() {
        var draft = TrimDraft(duration: 100)
        draft.setEnd(60)
        draft.setEnd(100)
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func aPendingEditOpensWithItsHandlesAndNoChanges() {
        let draft = TrimDraft(duration: 100, saved: TrimRange(start: 20, end: 50))
        #expect(draft.range == TrimRange(start: 20, end: 50))
        #expect(draft.isTrimmed)
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func draggingAPendingEditBackToFullLengthIsAChangeThatRemovesIt() {
        var draft = TrimDraft(duration: 100, saved: TrimRange(start: 20, end: 50))
        draft.setStart(0)
        draft.setEnd(100)

        #expect(!draft.isTrimmed)
        #expect(draft.hasUnsavedChanges)
        #expect(draft.result == nil, "Saving keeps the whole video")
    }

    @Test func resetGoesBackToWhatsSaved() {
        var fresh = TrimDraft(duration: 100)
        fresh.setStart(30)
        fresh.reset()
        #expect(!fresh.hasUnsavedChanges)
        #expect(!fresh.isTrimmed)

        var pending = TrimDraft(duration: 100, saved: TrimRange(start: 20, end: 50))
        pending.setEnd(90)
        pending.reset()
        #expect(pending.range == TrimRange(start: 20, end: 50))
        #expect(!pending.hasUnsavedChanges)
    }

    @Test func theHandlesKeepTheMinimumSelectionApart() {
        var draft = TrimDraft(duration: 100)
        draft.setEnd(40)
        draft.setStart(80)
        #expect(draft.range.start == 40 - TrimDraft.minimumSelection)
        draft.setEnd(0)
        #expect(draft.range.end == draft.range.start + TrimDraft.minimumSelection)
        draft.setStart(-5)
        #expect(draft.range.start == 0)
    }

    @Test func aSavedTrimIsClampedToTheVideosLength() {
        // Saved against 100 s; the asset loads a hair shorter.
        let draft = TrimDraft(duration: 99.98, saved: TrimRange(start: 20, end: 100))
        #expect(draft.range == TrimRange(start: 20, end: 99.98))
        #expect(!draft.hasUnsavedChanges)
    }

    @Test(arguments: [(4.9, false), (5, true), (120, true)])
    func shortClipsCantBeTrimmed(duration: Double, trimmable: Bool) {
        #expect(TrimDraft.canTrim(duration: duration) == trimmable)
    }
}
