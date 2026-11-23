import SwiftUI

/// Picks the face for a feed card and wires its interactions to the view model.
struct CardContentView: View {
    @Environment(FeedViewModel.self) private var vm
    let card: FeedCard
    var onOpenReview: (ReviewSet) -> Void = { _ in }
    var onPlayVideo: (LibraryItem) -> Void = { _ in }
    var onOpenPhoto: (LibraryItem) -> Void = { _ in }
    /// Single photo and video cards show a Share button (JUN-8). Only the main feed's deck asks for it, so a
    /// bundle's one-by-one review never shows one.
    var allowsShare = false

    var body: some View {
        switch card {
        case .photo(let item):
            PhotoCardView(item: item, onOpen: { onOpenPhoto(item) }, share: shareState(item), onShare: { vm.share(item) })
        case .video(let item):
            VideoCardView(item: item, onPlay: { onPlayVideo(item) }, share: shareState(item), onShare: { vm.share(item) })
        case .similar(let group):
            SimilarShotsCardView(
                group: group,
                marked: vm.markedForClearing(in: group),
                onToggle: { vm.toggleMark($0, in: group) },
                onOpen: { onOpenReview(ReviewSet(group: group, startingAt: $0)) }
            )
        case .duplicates(let group):
            DuplicatesCardView(
                group: group,
                marked: vm.markedForClearing(in: group),
                onOpen: { onOpenReview(ReviewSet(duplicates: group, startingAt: $0)) }
            )
        case .batch(let batch):
            ScreenshotBatchCardView(batch: batch) { onOpenReview(ReviewSet(batch: batch)) }
        }
    }

    private func shareState(_ item: LibraryItem) -> ShareButtonState? {
        allowsShare ? vm.shareButton(for: item) : nil
    }
}

#if DEBUG
#Preview {
    CardContentView(card: PreviewSamples.session.cards[12])
        .environment(FeedViewModel.mock())
        .padding(14)
        .paperBackground()
}
#endif
