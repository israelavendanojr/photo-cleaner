import SwiftUI

/// Goes through a card's items one at a time on the same deck as the main feed:
/// a batch of screenshots, or a set of similar shots.
///
/// Decisions go out together through `onFinish` once the last item is swiped.
/// Closing early keeps them as a draft on the view model, and reopening picks up where it left off.
/// A Live Photo flattened full screen (JUN-79) counts as kept here, and its flatten goes out with the
/// decisions; it costs no swipe of its own, and the review's Undo takes it back.
struct ItemReviewView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    let set: ReviewSet
    let onFinish: ([LibraryItem.ID: Decision], [LibraryItem.ID: PendingEdit]) -> Void

    /// The set in the order the deck shows it: drafted items first, so undo can reach them.
    private let items: [LibraryItem]
    @State private var index: Int
    @State private var decisions: [LibraryItem.ID: Decision]
    /// Flattens, by the item they're for.
    @State private var edits: [LibraryItem.ID: PendingEdit]
    @State private var request: SwipeDirection?
    @State private var addedBytes: Int64?
    @State private var returning: ReturningCard?

    init(set: ReviewSet, draft: [LibraryItem.ID: Decision] = [:], draftEdits: [LibraryItem.ID: PendingEdit] = [:],
         onFinish: @escaping ([LibraryItem.ID: Decision], [LibraryItem.ID: PendingEdit]) -> Void) {
        self.set = set
        self.onFinish = onFinish
        items = set.visitOrder(draft: draft)
        _decisions = State(initialValue: draft)
        _edits = State(initialValue: draftEdits)
        _index = State(initialValue: items.firstIndex { draft[$0.id] == nil } ?? items.count)
    }

    private var cards: [FeedCard] { items.map(FeedCard.init(item:)) }
    private var clearBytes: Int64 {
        items.filter { decisions[$0.id] == .delete }.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, DS.Spacing.m)
            SwipeDeck(
                cards: cards,
                index: index,
                returning: returning,
                label: vm.swipeLabel,
                onDecide: { decide($0, card: $1) },
                request: $request,
                onEdit: { edit, card in decide(.right, card: card, edit: edit) },
                photoEditOptions: vm.photoEditOptions
            )
        }
        #if DEBUG
        .overlay(alignment: .top) { BestPickMarker(isBestPick: isOnBestPick) }
        #endif
        .paperBackground()
    }

    /// Whether the top card is the set's suggested keeper.
    private var isOnBestPick: Bool {
        guard let bestID = set.bestID, items.indices.contains(index) else { return false }
        return items[index].id == bestID
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
                CircleIconButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "Undo", action: undo)
                    .disabled(index == 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DeckProgress(
                title: set.title,
                position: min(index + 1, items.count),
                total: items.count,
                value: Double(index) / Double(max(items.count, 1))
            )
            ToClearCounter(bytes: clearBytes, addedBytes: addedBytes, addedID: index)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// `edit` is a flatten from full screen, which keeps the photo.
    private func decide(_ direction: SwipeDirection, card: FeedCard, edit: PendingEdit? = nil) {
        guard let item = card.items.first else { return }
        let decision: Decision = switch direction {
        case .left: .delete
        case .right: .keep
        case .up: .later
        }
        if decision == .delete { Haptics.delete() }
        decisions[item.id] = decision
        edits[item.id] = decision == .keep && edit?.isFlatten == true ? edit : nil
        returning = nil
        addedBytes = decision == .delete ? item.bytes : nil
        index += 1
        if index >= items.count { onFinish(decisions, edits) } else { vm.saveDraft(decisions, edits: edits, for: set.id) }
    }

    private func undo() {
        guard index > 0 else { return }
        withAnimation(DS.Motion.calm) {
            index -= 1
            let item = items[index]
            // The side it left from, so it comes back that way.
            let direction: SwipeDirection = switch decisions[item.id] {
            case .delete: .left
            case .later: .up
            case .keep, nil: .right
            }
            returning = ReturningCard(cardID: FeedCard(item: item).id, direction: direction)
            decisions[item.id] = nil
            edits[item.id] = nil
            addedBytes = nil
        }
        vm.saveDraft(decisions, edits: edits, for: set.id)
    }
}

#if DEBUG
/// Tells UI tests whether the review is on the best pick, now that the card doesn't say.
/// Only with the mock library.
private struct BestPickMarker: View {
    let isBestPick: Bool

    var body: some View {
        if LibraryServices.usesMock {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(isBestPick ? "best pick" : "other")
                .accessibilityIdentifier("review.bestPick")
        }
    }
}

#Preview("Batch") {
    ItemReviewView(set: ReviewSet(batch: PreviewSamples.screenshotBatch)) { _, _ in }
        .environment(FeedViewModel.mock())
}

#Preview("Similar") {
    ItemReviewView(set: ReviewSet(group: PreviewSamples.similarGroup, startingAt: PreviewSamples.similarGroup.bestID)) { _, _ in }
        .environment(FeedViewModel.mock())
}
#endif
