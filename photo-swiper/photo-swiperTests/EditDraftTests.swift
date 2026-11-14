import Testing
@testable import photo_swiper

/// The full-screen video's edit against what's saved (JUN-50): leaving asks first when the trim or the
/// compression level changed, and saving gives the pending edit, or nil to remove it.
@MainActor
struct EditDraftTests {
    private let quarter = TrimRange(start: 0, end: 25)

    // MARK: Unsaved changes

    @Test func nothingChangedLeavesWithoutAsking() {
        #expect(!EditDraft(duration: 100).hasUnsavedChanges)
        let saved = PendingEdit(range: quarter, originalDuration: 100, compression: .max)
        #expect(!EditDraft(duration: 100, saved: saved).hasUnsavedChanges)
    }

    @Test func movingAHandleIsAChange() {
        var draft = EditDraft(duration: 100)
        draft.trim?.setEnd(25)
        #expect(draft.hasUnsavedChanges)
    }

    @Test func choosingALevelIsAChange() {
        var draft = EditDraft(duration: 100)
        draft.setCompression(.balanced)
        #expect(draft.hasUnsavedChanges)

        draft.setCompression(nil)
        #expect(!draft.hasUnsavedChanges, "Back to what's saved")
    }

    @Test func changingTheSavedLevelIsAChange() {
        var draft = EditDraft(duration: 100, saved: PendingEdit(originalDuration: 100, compression: .light))
        draft.setCompression(.max)
        #expect(draft.hasUnsavedChanges)
    }

    @Test func resetGoesBackToTheSavedTrimAndLevel() {
        let saved = PendingEdit(range: quarter, originalDuration: 100, compression: .light)
        var draft = EditDraft(duration: 100, saved: saved)
        draft.trim?.setEnd(100)
        draft.setCompression(.max)

        draft.reset()

        #expect(!draft.hasUnsavedChanges)
        #expect(draft.range == quarter)
        #expect(draft.compression == .light)
    }

    // MARK: Result

    @Test func aTrimAndALevelSaveAsOneEdit() {
        var draft = EditDraft(duration: 100)
        draft.trim?.setEnd(25)
        draft.setCompression(.balanced)

        #expect(draft.result(compressedBytes: 20_000_000)
            == PendingEdit(range: quarter, originalDuration: 100, compression: .balanced, compressedBytes: 20_000_000))
    }

    /// None removes the compression and keeps the trim.
    @Test func choosingNoneWithATrimKeepsTheTrim() {
        var draft = EditDraft(duration: 100, saved: PendingEdit(range: quarter, originalDuration: 100, compression: .max,
                                                                compressedBytes: 5_000_000))
        draft.setCompression(nil)

        #expect(draft.hasUnsavedChanges)
        #expect(draft.result(compressedBytes: nil) == PendingEdit(range: quarter, originalDuration: 100))
    }

    /// None without a trim leaves nothing: saving removes the pending edit.
    @Test func choosingNoneWithoutATrimRemovesTheEdit() {
        var draft = EditDraft(duration: 100, saved: PendingEdit(originalDuration: 100, compression: .max))
        draft.setCompression(nil)

        #expect(draft.hasUnsavedChanges)
        #expect(draft.result(compressedBytes: nil) == nil)
    }

    @Test func theEstimateIsDroppedWithoutALevel() {
        var draft = EditDraft(duration: 100)
        draft.trim?.setEnd(25)
        #expect(draft.result(compressedBytes: 9_000_000)?.compressedBytes == nil)
    }

    // MARK: Trimming off

    /// With the trimmer off, the strip is a seek bar: only the level can change, and a saved trim stays.
    @Test func withTrimmingOffOnlyTheLevelChanges() {
        var draft = EditDraft(duration: 100, saved: PendingEdit(range: quarter, originalDuration: 100), canTrim: false)
        #expect(draft.trim == nil)
        #expect(draft.range == quarter)
        #expect(!draft.hasUnsavedChanges)

        draft.setCompression(.light)
        #expect(draft.result(compressedBytes: nil) == PendingEdit(range: quarter, originalDuration: 100, compression: .light))
    }

    @Test func aClipTooShortToTrimCanStillBeCompressed() {
        var draft = EditDraft(duration: 3)
        #expect(draft.trim == nil)
        draft.setCompression(.max)
        #expect(draft.result(compressedBytes: 100)?.compression == .max)
    }

    // MARK: Summary

    @Test func theSummarySaysWhatTheEditKeepsAndSaves() {
        var draft = EditDraft(duration: 100)
        draft.trim?.setEnd(25)
        let trimmed = VideoPreviewView.summary(draft, bytes: 400_000_000, compressedBytes: nil)
        #expect(trimmed.change == "1:40 · \(Format.size(400_000_000)) → 0:25 · ~\(Format.size(100_000_000))")
        #expect(trimmed.saves == "saves ~\(Format.size(300_000_000))")

        draft.setCompression(.balanced)
        let both = VideoPreviewView.summary(draft, bytes: 400_000_000, compressedBytes: 20_000_000)
        #expect(both.change == "1:40 · \(Format.size(400_000_000)) → 0:25 · ~\(Format.size(20_000_000))")
        #expect(both.saves == "saves ~\(Format.size(380_000_000))", "Trim and compression together")

        var removing = EditDraft(duration: 100, saved: PendingEdit(range: quarter, originalDuration: 100))
        removing.trim?.setEnd(100)
        #expect(VideoPreviewView.summary(removing, bytes: 400_000_000, compressedBytes: nil).saves == nil)
    }

    // MARK: Preview window

    @Test func thePreviewIsThreeSecondsAroundThePlayheadInsideTheTrim() {
        let range = TrimRange(start: 10, end: 40)
        #expect(CompressionPreviewer.window(around: 20, within: range) == TrimRange(start: 18.5, end: 21.5))
        #expect(CompressionPreviewer.window(around: 10.5, within: range) == TrimRange(start: 10, end: 13), "Kept inside at the start")
        #expect(CompressionPreviewer.window(around: 60, within: range) == TrimRange(start: 37, end: 40), "And at the end")
        #expect(CompressionPreviewer.window(around: 1, within: TrimRange(start: 0, end: 2)) == TrimRange(start: 0, end: 2),
                "A shorter trim is previewed whole")
    }
}
