import SwiftUI

/// Shown when the feed has nothing left: a calm stop, not a dead end.
struct CaughtUpView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Circle()
                .strokeBorder(DS.Palette.brick, lineWidth: 2)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("All caught up.")
                .dsSerif(34, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.ink)
                .padding(.top, DS.Spacing.l)
            Text(vm.feedFocus.map { "No more \($0.phrase) for now." } ?? "Nothing left to look at. Enjoy the space.")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.xs)
            if vm.freedBytes > 0 {
                Text("\(Text(Format.size(vm.freedBytes)).font(.system(.title3, design: .serif)).foregroundStyle(DS.Palette.brick)) freed so far")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
                    .padding(.top, DS.Spacing.l)
            }
            Spacer()
            Button(isChecking ? "Checking…" : "Check again", action: checkAgain)
                .buttonStyle(.pill(.ink))
                .disabled(isChecking)
                .accessibilityIdentifier("caughtUp.checkAgain")
            if let focus = vm.feedFocus {
                // Caught up on one kind only: the rest of the library is still there.
                Button("Show everything") { vm.focusFeed(on: nil) }
                    .buttonStyle(.pill(.ghost))
                    .accessibilityHint("Stops showing only \(focus.phrase)")
                    .accessibilityIdentifier("caughtUp.showEverything")
            }
            if vm.feedSort == .newest || vm.feedSort == .oldest {
                // Items with no date taken only show under Recommended and Largest.
                Button("Sort by Recommended") { vm.sortFeed(by: .recommended) }
                    .buttonStyle(.pill(.ghost))
                    .accessibilityHint("Also shows items with no date")
                    .accessibilityIdentifier("caughtUp.sortRecommended")
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DS.Spacing.xxl)
        .padding(.bottom, DS.Spacing.m)
        .paperBackground()
    }

    /// Back to the feed if new photos turned up, or "later" ones are due again.
    private func checkAgain() {
        isChecking = true
        Task {
            await vm.checkAgain()
            isChecking = false
        }
    }
}

#if DEBUG
#Preview {
    CaughtUpView()
        .environment(FeedViewModel.mock(startingAt: .caughtUp))
}
#endif
