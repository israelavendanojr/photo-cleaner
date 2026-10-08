import SwiftUI

/// Picks the face for a feed card and wires its interactions to the view model.
struct CardContentView: View {
    @Environment(FeedViewModel.self) private var vm
    let card: FeedCard

    var body: some View {
        switch card {
        case .photo(let item):
            PhotoCardView(item: item)
        case .video(let item):
            VideoCardView(item: item)
        case .similar(let group):
            SimilarShotsCardView(group: group, marked: vm.markedForClearing(in: group)) { id in
                vm.toggleMark(id, in: group)
            }
        case .batch(let batch):
            ScreenshotBatchCardView(batch: batch)
        }
    }
}

#Preview {
    CardContentView(card: PreviewSamples.session.cards[12])
        .environment(FeedViewModel.mock())
        .padding(14)
        .background(DS.Palette.paper)
}
