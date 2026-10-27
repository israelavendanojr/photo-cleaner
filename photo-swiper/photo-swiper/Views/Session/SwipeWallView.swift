import SwiftUI

/// Out of free swipes. A sheet over the deck, opened by a refused swipe: when the next refill
/// lands, what's left in the user's own numbers, the unlock, and a reminder. Deleting lives in the pile.
struct SwipeWallView: View {
    @Environment(FeedViewModel.self) private var vm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let estimate = vm.clutterEstimate {
                    whatsLeft(estimate)
                        .padding(.top, DS.Spacing.l)
                }
                if vm.freedBytes > 0 {
                    Text("Freed so far: \(Format.size(vm.freedBytes))")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.secondary)
                        .padding(.top, DS.Spacing.m)
                }
                UnlockOffer { vm.dismissWall() }
                    .padding(.top, DS.Spacing.l)
                if vm.canRemind {
                    reminder
                        .padding(.top, DS.Spacing.m)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.Palette.paper)
        .interactiveDismissDisabled(vm.isPurchaseBusy)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Out of swipes")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .accessibilityAddTraits(.isHeader)
            if let next = vm.nextRefillAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("+\(vm.allowanceTunables.refillAmount) in \(Format.countdown(next.timeIntervalSince(context.date)))")
                        .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                        .foregroundStyle(DS.Palette.ink)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("wall.countdown")
            }
        }
    }

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
            if let days = vm.daysToFinish, days >= 2 {
                Text("At this pace, \(Format.roughDays(days)). Unlock to finish today.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Spacing.xs)
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
                .frame(maxWidth: .infinity, minHeight: 44)
        } else if vm.areRemindersDenied {
            Text("Notifications are off for \(AppInfo.name). You can turn them on in Settings.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Button {
                Task { await vm.remindWhenSwipesAreBack() }
            } label: {
                Label("Remind me when swipes are back", systemImage: "bell")
            }
            .buttonStyle(.pill(.ghost))
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
