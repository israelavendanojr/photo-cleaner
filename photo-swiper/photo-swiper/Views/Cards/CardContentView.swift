import SwiftUI

/// Picks the face for a feed card and wires its interactions to the view model.
struct CardContentView: View {
    @Environment(FeedViewModel.self) private var vm
    let card: FeedCard
    var onOpenReview: (ReviewSet) -> Void = { _ in }
    var onPlayVideo: (LibraryItem) -> Void = { _ in }
    var onOpenPhoto: (LibraryItem) -> Void = { _ in }

    var body: some View {
        switch card {
        case .photo(let item):
            PhotoCardView(item: item) { onOpenPhoto(item) }
        case .video(let item):
            VideoCardView(item: item) { onPlayVideo(item) }
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
}

#if DEBUG
#Preview {
    CardContentView(card: PreviewSamples.session.cards[12])
        .environment(FeedViewModel.mock())
        .padding(14)
        .background(DS.Palette.paper)
}
#endif
