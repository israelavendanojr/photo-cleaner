import SwiftUI

/// A quiet caption under the deck until the first decision. The nudge's stamps show the rest.
struct SwipeHint: View {
    var body: some View {
        Text("Swipe to sort")
            .font(.footnote.weight(.medium))
            .foregroundStyle(DS.Palette.secondary)
            .allowsHitTesting(false)
            .accessibilityLabel("Swipe left to delete, right to keep, or up for later")
    }
}

/// A first-time demo on the real top card: it leans left far enough for the Delete stamp to
/// show, then right for Keep, without reaching the commit threshold.
enum SwipeNudge {
    /// Short of `SwipeThresholds.horizontal`, so nothing arms or fires a haptic.
    static let reach: CGFloat = 95
    static let firstDelay = Duration.seconds(1.2)
    /// How long the card must be left alone before the demo plays again.
    static let idleBeforeReplay = Duration.seconds(5)
    /// The first run and up to two replays.
    static let maxRuns = 3

    /// Moves the card through the demo. `move` returns false when the user has taken over,
    /// which ends the demo where it is.
    @MainActor
    static func perform(_ move: (CGSize) -> Bool) async throws {
        for (x, hold) in [(-reach, 0.75), (0, 0.35), (reach, 0.75), (0, 0)] {
            var moved = false
            withAnimation(DS.Motion.calm) { moved = move(CGSize(width: x, height: 0)) }
            guard moved else { return }
            if hold > 0 { try await Task.sleep(for: .seconds(hold)) }
        }
    }
}

#Preview {
    VStack {
        PhotoCardView(item: PreviewSamples.plainPhoto)
            .padding(14)
        SwipeHint()
    }
    .background(DS.Palette.paper)
}
