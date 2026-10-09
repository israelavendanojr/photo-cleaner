import SwiftUI

/// Goes through a batch one item at a time with the feed's own swipe vocabulary.
///
/// Decisions stay local until the last item is swiped, then go out together through `onFinish`.
/// Closing early changes nothing.
struct BatchReviewView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    let batch: ItemBatch
    let onFinish: ([LibraryItem.ID: Decision]) -> Void

    @State private var index = 0
    @State private var decisions: [LibraryItem.ID: Decision] = [:]
    @State private var request: SwipeDirection?
    /// How far the top card is toward committing, 0...1.
    @State private var progress = 0.0
    @State private var addedBytes: Int64?
    /// The side each decided item left from, so undo can bring it back that way.
    @State private var directions: [SwipeDirection] = []
    @State private var returning: (id: LibraryItem.ID, direction: SwipeDirection)?

    private var items: [LibraryItem] { batch.items }
    private var visibleItems: [LibraryItem] { Array(items.dropFirst(index).prefix(2)) }
    private var clearBytes: Int64 {
        items.filter { decisions[$0.id] == .delete }.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, DS.Spacing.m)
            ZStack {
                ForEach(visibleItems) { item in
                    let isTop = item.id == items[safe: index]?.id
                    SwipeableCard(
                        isEnabled: isTop,
                        entrance: item.id == returning?.id ? returning?.direction : nil,
                        label: { vm.swipeLabel($0, for: .photo(item)) },
                        request: isTop ? $request : .constant(nil),
                        progress: isTop ? $progress : .constant(0),
                        onSwipe: { decide($0, item: item) }
                    ) {
                        PhotoCardView(item: item)
                    }
                    .scaleEffect(isTop ? 1 : 0.95 + 0.05 * progress)
                    .offset(y: isTop ? 0 : 12 * (1 - progress))
                    .allowsHitTesting(isTop)
                    .zIndex(isTop ? 1 : 0)
                    .transition(isTop ? .identity : .opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.horizontal, DS.Spacing.cardInset)
            .frame(maxHeight: .infinity)

            ActionBar { request = $0 }
                .disabled(index >= items.count)
        }
        .background(DS.Palette.paper)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                circleButton("xmark", label: "Close") { dismiss() }
                circleButton("arrow.uturn.backward", label: "Undo", action: undo)
                    .disabled(index == 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                Text(batch.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                Text("\(min(index + 1, items.count)) of \(items.count)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.secondary)
                    .contentTransition(.numericText(value: Double(index)))
                ProgressLine(value: Double(index) / Double(max(items.count, 1)))
                    .frame(width: 96)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            ToClearCounter(bytes: clearBytes, addedBytes: addedBytes, addedID: index)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func circleButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Palette.secondary)
                .frame(width: 44, height: 44)
                .overlay { Circle().strokeBorder(DS.Palette.line, lineWidth: 1.5) }
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    private func decide(_ direction: SwipeDirection, item: LibraryItem) {
        let decision: Decision = switch direction {
        case .left: .delete
        case .right: .keep
        case .up: .later
        }
        if decision == .delete { Haptics.delete() }
        withAnimation(DS.Motion.calm) {
            progress = 0
            decisions[item.id] = decision
            directions.append(direction)
            returning = nil
            addedBytes = decision == .delete ? item.bytes : nil
            index += 1
        }
        if index >= items.count { onFinish(decisions) }
    }

    private func undo() {
        guard index > 0 else { return }
        withAnimation(DS.Motion.calm) {
            index -= 1
            returning = (items[index].id, directions.removeLast())
            decisions[items[index].id] = nil
            addedBytes = nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

#Preview {
    BatchReviewView(batch: PreviewSamples.screenshotBatch) { print($0) }
        .environment(FeedViewModel.mock())
}
