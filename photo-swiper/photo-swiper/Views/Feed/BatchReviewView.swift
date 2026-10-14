import SwiftUI

/// Goes through a batch one item at a time on the same deck as the main feed.
///
/// Decisions go out together through `onFinish` once the last item is swiped.
/// Closing early keeps them as a draft on the view model, and reopening picks up where it left off.
struct BatchReviewView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    let batch: ItemBatch
    let onFinish: ([LibraryItem.ID: Decision]) -> Void

    @State private var index: Int
    @State private var decisions: [LibraryItem.ID: Decision]
    @State private var request: SwipeDirection?
    @State private var addedBytes: Int64?
    @State private var returning: FeedViewModel.ReturningCard?

    init(batch: ItemBatch, draft: [LibraryItem.ID: Decision] = [:], onFinish: @escaping ([LibraryItem.ID: Decision]) -> Void) {
        self.batch = batch
        self.onFinish = onFinish
        _decisions = State(initialValue: draft)
        _index = State(initialValue: batch.items.firstIndex { draft[$0.id] == nil } ?? batch.items.count)
    }

    private var items: [LibraryItem] { batch.items }
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
                onDecide: decide,
                request: $request
            )
        }
        .background(DS.Palette.paper)
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
                title: batch.label,
                position: min(index + 1, items.count),
                total: items.count,
                value: Double(index) / Double(max(items.count, 1))
            )
            ToClearCounter(bytes: clearBytes, addedBytes: addedBytes, addedID: index)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func decide(_ direction: SwipeDirection, card: FeedCard) {
        guard let item = card.items.first else { return }
        let decision: Decision = switch direction {
        case .left: .delete
        case .right: .keep
        case .up: .later
        }
        if decision == .delete { Haptics.delete() }
        decisions[item.id] = decision
        returning = nil
        addedBytes = decision == .delete ? item.bytes : nil
        index += 1
        if index >= items.count { onFinish(decisions) } else { vm.saveDraft(decisions, for: batch) }
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
            returning = FeedViewModel.ReturningCard(cardID: FeedCard(item: item).id, direction: direction)
            decisions[item.id] = nil
            addedBytes = nil
        }
        vm.saveDraft(decisions, for: batch)
    }
}

#Preview {
    BatchReviewView(batch: PreviewSamples.screenshotBatch) { print($0) }
        .environment(FeedViewModel.mock())
}
