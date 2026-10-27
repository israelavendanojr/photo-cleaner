import SwiftUI

/// The swipeable stack every feed is built on: the top card, the card peeking behind it,
/// the action buttons, full-screen previews, and image pre-caching.
///
/// It only shows cards and reports swipes. What a swipe means is up to the caller, so the
/// main feed and a card's one-by-one review get the same feel from the same code.
struct SwipeDeck: View {
    let cards: [FeedCard]
    let index: Int
    /// The card an undo just restored, and the side it comes back from.
    let returning: FeedViewModel.ReturningCard?
    /// Overlay text for each direction on a card.
    let label: (SwipeDirection, FeedCard) -> String
    /// Called inside the deck's animation once a swipe commits. The caller advances `index`.
    let onDecide: (SwipeDirection, FeedCard) -> Void
    /// Set to swipe the top card in code. The action buttons use it too.
    @Binding var request: SwipeDirection?
    /// A batch or similar-shots card asked to be gone through one by one.
    var onOpenReview: (ReviewSet) -> Void = { _ in }
    /// Marks a set's best pick with its reason. Only the one-by-one review has one.
    var bestPickReason: (FeedCard) -> String? = { _ in nil }
    /// Shows the swipe caption and plays the swipe demo on the top card.
    var showsHint = false
    /// Deals the cards in from above when the deck first appears (straight after onboarding).
    var dealsIn = false
    /// False when the top card can't be swiped that way. Asked as a swipe commits. The card then
    /// flies out and rewinds into place, nothing is decided, and `onRefused` is called once it's back.
    var canSwipe: (SwipeDirection) -> Bool = { _ in true }
    var onRefused: (SwipeDirection) -> Void = { _ in }
    /// Shown in place of the top card while the deck waits on more, e.g. "Finding more…".
    var waitingText: String?

    /// How far the top card is toward committing, 0...1.
    @State private var progress = 0.0
    @State private var cardSize = CGSize.zero
    /// Cards already decided but still flying off. They stay in the stack until the animation
    /// ends, so the next card is live the moment the previous one is released.
    @State private var departing: [FeedCard] = []
    /// The video open in the full-screen player.
    @State private var previewingVideo: LibraryItem?
    /// The photo open full screen.
    @State private var previewingPhoto: LibraryItem?
    /// A swipe made in full screen. The top card flies off that way once the preview closes.
    @State private var previewDecision: SwipeDirection?
    /// What was pre-cached before this deck appeared, handed back when it goes (a nested deck).
    @State private var outerPreheat: [String: CGSize]?
    @State private var hasDealt = false
    @Environment(\.displayScale) private var displayScale

    private var currentCard: FeedCard? { cards.indices.contains(index) ? cards[index] : nil }
    private var nextCard: FeedCard? { cards.indices.contains(index + 1) ? cards[index + 1] : nil }
    private var isDealt: Bool { hasDealt || !dealsIn }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if currentCard == nil, let waitingText {
                    WaitingCard(text: waitingText)
                        .transition(.opacity)
                }
                // One ForEach keyed by card ID so a card keeps its identity as it moves
                // between "behind" and "on top" (promotion after a swipe, demotion on undo).
                ForEach(visibleCards) { card in
                    let isTop = card.id == currentCard?.id
                    let isDeparting = !isTop && departing.contains { $0.id == card.id }
                    let isFront = isTop || isDeparting
                    SwipeableCard(
                        isEnabled: isTop,
                        entrance: entrance(for: card),
                        label: { label($0, card) },
                        request: isTop ? $request : .constant(nil),
                        progress: isTop ? $progress : .constant(0),
                        onRelease: { release($0, card: card) },
                        onSwipe: { finish($0, card: card) },
                        nudges: isTop && showsHint,
                        canCommit: { !isTop || canSwipe($0) },
                        onRefused: onRefused
                    ) {
                        CardContentView(
                            card: card,
                            bestPickReason: bestPickReason(card),
                            onOpenReview: onOpenReview,
                            onPlayVideo: { previewingVideo = $0 },
                            onOpenPhoto: { previewingPhoto = $0 }
                        )
                    }
                    .scaleEffect(isFront ? 1 : 0.95 + 0.05 * progress)
                    .offset(y: isFront ? 0 : 12 * (1 - progress))
                    .modifier(DealIn(isDealt: isDealt, order: isTop ? 1 : 0))
                    .allowsHitTesting(isTop)
                    .zIndex(isDeparting ? 2 : isTop ? 1 : 0)
                    .transition(isFront ? .identity : .opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { cardSize = $0 }
            .padding(.horizontal, DS.Spacing.cardInset)
            .frame(maxHeight: .infinity)

            ActionBar { request = $0 }
                .disabled(currentCard == nil)
                .overlay(alignment: .top) {
                    // In the gap above the lowered Later button, without taking space, so
                    // nothing moves when it goes.
                    if showsHint {
                        SwipeHint()
                            .transition(.opacity)
                    }
                }
                .modifier(DealIn(isDealt: isDealt, order: 2))
        }
        .fullScreenCover(item: $previewingVideo, onDismiss: flyOutPreviewDecision) { item in
            VideoPreviewView(item: item, label: previewLabel) { direction in
                previewDecision = direction
                previewingVideo = nil
            }
        }
        .fullScreenCover(item: $previewingPhoto, onDismiss: flyOutPreviewDecision) { item in
            PhotoPreviewView(item: item, label: previewLabel) { direction in
                previewDecision = direction
                previewingPhoto = nil
            }
        }
        .onChange(of: returning) { _, returning in
            // Undo can bring back a card that is still flying; it's the top card again.
            guard let returning else { return }
            departing.removeAll { $0.id == returning.cardID }
        }
        .onAppear {
            outerPreheat = ThumbnailPipeline.shared.preheated
            if dealsIn { hasDealt = true }
        }
        .onDisappear {
            if let outerPreheat { ThumbnailPipeline.shared.preheat(outerPreheat) }
        }
        .task(id: preheatWindow) {
            ThumbnailPipeline.shared.preheat(preheatWindow)
        }
    }

    /// Library images for the cards on screen and the next few, at the sizes they'll be shown,
    /// so swiping never lands on a blank card. Everything outside the window is released.
    private var preheatWindow: [String: CGSize] {
        guard cardSize != .zero else { return [:] }
        let cardPixels = ThumbnailPipeline.pixelSize(for: cardSize, scale: displayScale)
        let tilePixels = ThumbnailPipeline.pixelSize(for: ScreenshotBatchCardView.tileSize, scale: displayScale)
        var window: [String: CGSize] = [:]
        for card in cards.dropFirst(index).prefix(6) {
            switch card {
            case .photo(let item), .video(let item):
                if let id = item.image.localIdentifier { window[id] = cardPixels }
            case .batch(let batch):
                for item in batch.items.prefix(ScreenshotBatchCardView.fannedCount) {
                    if let id = item.image.localIdentifier { window[id] = tilePixels }
                }
            case .similar:
                break
            }
        }
        return window
    }

    private var visibleCards: [FeedCard] {
        let stack = [currentCard, nextCard].compactMap { $0 }
        return departing.filter { card in !stack.contains { $0.id == card.id } } + stack
    }

    private func previewLabel(_ direction: SwipeDirection) -> String {
        currentCard.map { label(direction, $0) } ?? ""
    }

    /// Once a preview closes on a decision, the card leaves like an action-button swipe.
    private func flyOutPreviewDecision() {
        guard let direction = previewDecision else { return }
        previewDecision = nil
        request = direction
    }

    private func entrance(for card: FeedCard) -> SwipeDirection? {
        guard let returning, returning.cardID == card.id else { return nil }
        return returning.direction
    }

    /// Decides as soon as the card is released, unless it's the last one: that one finishes
    /// flying first so whatever comes after the deck doesn't cut it off.
    private func release(_ direction: SwipeDirection, card: FeedCard) {
        guard nextCard != nil else { return }
        departing.append(card)
        commit(direction, card: card)
    }

    private func finish(_ direction: SwipeDirection, card: FeedCard) {
        if let i = departing.firstIndex(where: { $0.id == card.id }) {
            departing.remove(at: i)
        } else {
            commit(direction, card: card)
        }
    }

    private func commit(_ direction: SwipeDirection, card: FeedCard) {
        withAnimation(DS.Motion.calm) {
            progress = 0
            onDecide(direction, card)
        }
    }
}

/// A quiet stand-in for the top card while more are on the way.
private struct WaitingCard: View {
    let text: String

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .fill(DS.Palette.muted)
            .overlay {
                VStack(spacing: DS.Spacing.s) {
                    ProgressView()
                        .tint(DS.Palette.secondary)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(DS.Palette.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
            .accessibilityIdentifier("feed.findingMore")
    }
}

#if DEBUG
#Preview {
    @Previewable @State var index = 0
    @Previewable @State var request: SwipeDirection?
    let cards = PreviewSamples.session.cards

    SwipeDeck(
        cards: cards,
        index: index,
        returning: nil,
        label: { direction, _ in "\(direction)" },
        onDecide: { _, _ in index += 1 },
        request: $request
    )
    .environment(FeedViewModel.mock())
    .background(DS.Palette.paper)
}
#endif
