import SwiftUI

/// Picks the face for a feed card and wires its interactions to the view model.
struct CardContentView: View {
    @Environment(FeedViewModel.self) private var vm
    let card: FeedCard
    /// Shown with a "Best pick" chip on a single-photo card in a one-by-one review.
    var bestPickReason: String?
    var onOpenReview: (ReviewSet) -> Void = { _ in }
    var onPlayVideo: (LibraryItem) -> Void = { _ in }
    var onOpenPhoto: (LibraryItem) -> Void = { _ in }

    var body: some View {
        switch card {
        case .photo(let item):
            PhotoCardView(item: item, bestPickReason: bestPickReason) { onOpenPhoto(item) }
        case .video(let item):
            VideoCardView(item: item) { onPlayVideo(item) }
        case .similar(let group):
            SimilarShotsCardView(group: group, marked: vm.markedForClearing(in: group)) { id in
                vm.toggleMark(id, in: group)
            }
        case .batch(let batch):
            ScreenshotBatchCardView(batch: batch) { onOpenReview(ReviewSet(batch: batch)) }
        }
    }
}

#if DEBUG
#Preview {
    CardContentView(card: PreviewSamples.session.cards[12])
        .environment(FeedViewModel.mock())
        .padding(14)
        .background(DS.Palette.paper)
}
#endif
