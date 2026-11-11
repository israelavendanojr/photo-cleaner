import SwiftUI

/// Out of free swipes. A sheet over the deck, opened by a refused swipe, in the same layout as the
/// other unlock screens: when the next refill lands, the pace, a card of what's left in the user's own
/// numbers with the reminder, then the unlock. Deleting lives in the pile.
struct SwipeWallView: View {
    @Environment(FeedViewModel.self) private var vm

    var body: some View {
        UpsellLayout(
            eyebrow: vm.canSwipe ? "Ready to swipe" : "Out of swipes",
            supporting: UnlockCopy.wallSupporting(daysToFinish: vm.daysToFinish)
        ) {
            // Always says when swipes come back; the top bar no longer does.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(UnlockCopy.refillLine(canSwipe: vm.canSwipe, nextRefillAt: vm.nextRefillAt,
                                           refillAmount: vm.allowanceTunables.refillAmount, now: context.date))
                    .monospacedDigit()
            }
            .accessibilityIdentifier("wall.countdown")
        } context: {
            if hasContext {
                UpsellCard {
                    if let estimate = vm.clutterEstimate { whatsLeft(estimate) }
                    if vm.freedBytes > 0 {
                        Text("Freed so far: \(Format.size(vm.freedBytes))")
                            .font(.callout)
                            .foregroundStyle(DS.Palette.secondary)
                            .padding(.top, vm.clutterEstimate == nil ? 0 : DS.Spacing.xs)
                    }
                    if vm.canRemind {
                        reminder
                            .padding(.top, DS.Spacing.xs)
                    }
                }
            }
        } offer: {
            UnlockOffer { vm.dismissWall() }
        }
        .interactiveDismissDisabled(vm.isPurchaseBusy)
    }

    private var hasContext: Bool {
        vm.clutterEstimate != nil || vm.freedBytes > 0 || vm.canRemind
    }

    // MARK: Sections

    private func whatsLeft(_ estimate: ClutterEstimate) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Still to go, about")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
            if estimate.likelyClearBytes > 0 {
                line("\(Format.size(estimate.likelyClearBytes)) of likely clutter")
            }
            if estimate.similarGroupCount > 0 {
                line("\(Format.count(estimate.similarGroupCount)) \(estimate.similarGroupCount == 1 ? "set" : "sets") of similar shots")
            }
            if estimate.screenshotCount > 0 {
                line("\(Format.count(estimate.screenshotCount)) \(estimate.screenshotCount == 1 ? "screenshot" : "screenshots")")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(DS.Palette.ink)
    }

    @ViewBuilder
    private var reminder: some View {
        if vm.isRemindersOptedIn, !vm.areRemindersDenied {
            Label("We'll let you know when swipes are back", systemImage: "bell")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .frame(minHeight: 44)
        } else if vm.areRemindersDenied {
            Text("Notifications are off for \(AppInfo.name). You can turn them on in Settings.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button {
                Task { await vm.remindWhenSwipesAreBack() }
            } label: {
                Label("Remind me when swipes are back", systemImage: "bell")
                    .font(.callout.weight(.medium))
                    .frame(minHeight: 44)
            }
            .foregroundStyle(DS.Palette.ink)
            .accessibilityIdentifier("wall.remind")
        }
    }
}

#if DEBUG
#Preview("Out of swipes") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SwipeWallView()
        }
        .environment(FeedViewModel.mock(startingAt: .outOfSwipes))
}

#Preview("Purchasing") {
    let vm = FeedViewModel.mock(startingAt: .outOfSwipes)
    vm.previewWall(status: .purchasing)
    return SwipeWallView().environment(vm)
}

#Preview("Restore failed") {
    let vm = FeedViewModel.mock(startingAt: .outOfSwipes)
    vm.previewWall(status: .nothingToRestore)
    return SwipeWallView().environment(vm)
}
#endif
