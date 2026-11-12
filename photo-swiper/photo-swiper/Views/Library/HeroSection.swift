import SwiftUI

/// The top of the dashboard, one card: total space cleared, this week against last, how much of the
/// library is reviewed, and photos reviewed by day. Before anything is cleared the number is an invitation
/// to start instead.
///
/// The first time the tab is seen each launch, the number counts up from zero and the change fades up
/// under it once it lands. Later visits, and Reduce Motion, show it still.
struct HeroSection: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The dashboard's numbers, or a stand-in while they load.
    let snapshot: DashboardSnapshot
    /// The snapshot is a stand-in: the parts drawn from it are redacted. The rest is live.
    var isLoading = false
    /// Everything cleared. The history's total, or the view model's if a delete just landed before it.
    let clearedBytes: Int64
    /// The tab is on screen, so the entrance can be seen.
    var isActive = true

    /// What the number shows while it counts up; nil shows `clearedBytes`.
    @State private var countingBytes: Int64?
    @State private var isChangeShown = true

    var body: some View {
        DashboardCard {
            if clearedBytes > 0 {
                cleared
            } else {
                firstCleanup
            }
        } content: {
            reviewed
            if let reviews = snapshot.reviews, reviews.total > 0 {
                ReviewHeatmap(activity: reviews)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: clearedBytes)
        .task(id: isActive && !isLoading && clearedBytes > 0) { await playEntranceIfDue() }
    }

    /// The count-up hasn't played yet this launch, so the number waits at zero rather than flashing its total first.
    private var isEntranceDue: Bool {
        !vm.hasPlayedDashboardEntrance && !reduceMotion && !isLoading
    }

    private var cleared: some View {
        let shown = countingBytes ?? (isEntranceDue ? 0 : clearedBytes)
        return VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(Format.size(shown))
                .dsSerif(48, relativeTo: .largeTitle)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.brick)
                .contentTransition(.numericText(value: Double(shown)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let change = snapshot.weeklyChange {
                // Brick only when more was cleared: brick means space freed, and a drop isn't that. Ink, not
                // secondary, for a drop: it's essential small text, and secondary is below AA at this size.
                Text(Format.weeklyChange(change))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(change.isDown ? DS.Palette.ink : DS.Palette.brick)
                    .fixedSize(horizontal: false, vertical: true)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .opacity(isChangeShown && !isEntranceDue ? 1 : 0)
                    .offset(y: isChangeShown && !isEntranceDue ? 0 : DS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("library.cleared")
    }

    private var accessibilityText: String {
        let total = "\(Format.size(clearedBytes)) cleared"
        guard let change = snapshot.weeklyChange, !isLoading else { return total }
        return "\(total), \(Format.weeklyChange(change))"
    }

    /// Counts up from zero in `DS.Motion.countUpSteps` steps, easing out, then fades the change up.
    /// Once per launch, only where it can be seen, and never under Reduce Motion.
    private func playEntranceIfDue() async {
        guard isActive, !isLoading, clearedBytes > 0, !vm.hasPlayedDashboardEntrance else { return }
        guard !reduceMotion else {
            vm.markDashboardEntrancePlayed()
            return
        }
        let target = clearedBytes
        let steps = DS.Motion.countUpSteps
        // Set before the flag, in the same turn, so no frame shows the total between them.
        countingBytes = 0
        isChangeShown = false
        vm.markDashboardEntrancePlayed()
        for step in 1...steps {
            try? await Task.sleep(for: DS.Motion.countUpDuration / steps)
            // Leaving the tab mid-count lands the number at once.
            guard !Task.isCancelled else { break }
            let progress = 1 - pow(1 - Double(step) / Double(steps), 3)
            withAnimation(DS.Motion.calm) { countingBytes = Int64(Double(target) * progress) }
        }
        withAnimation(DS.Motion.calm) { countingBytes = nil }
        withAnimation(DS.Motion.gentle) { isChangeShown = true }
    }

    /// How much of the library has been looked at, kept or not.
    private var reviewed: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(Format.percent(vm.libraryReviewedFraction))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: vm.libraryReviewedFraction))
                Text("reviewed")
                    .font(.callout)
            }
            .foregroundStyle(DS.Palette.ink)
            ProgressLine(value: vm.libraryReviewedFraction)
            Text("\(Format.count(vm.libraryReviewedCount)) of \(Format.count(vm.stats.totalItems)) photos reviewed")
                .font(.footnote)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.reviewed")
    }

    /// Nothing cleared yet: say what this screen will show, and send them to the feed.
    private var firstCleanup: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Nothing cleared yet")
                .dsSerif(34, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Space you clear shows up here, week by week, with what's still worth a look.")
                .font(.callout)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start reviewing") { vm.showFeed() }
                .buttonStyle(.pill(.ink))
                .padding(.top, DS.Spacing.s)
                .accessibilityIdentifier("library.startReviewing")
        }
    }
}

#if DEBUG
private extension DashboardSnapshot {
    static func preview(thisWeek: Int64, lastWeek: Int64) -> DashboardSnapshot {
        var snapshot = DashboardSnapshot.preview
        snapshot.clearedThisWeek = thisWeek
        snapshot.clearedLastWeek = lastWeek
        return snapshot
    }
}

#Preview("Up on last week") {
    HeroSection(snapshot: .preview(thisWeek: 1_620_000_000, lastWeek: 1_200_000_000), clearedBytes: DashboardSnapshot.preview.totalCleared)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock(startingAt: .batch))
}

#Preview("Down on last week") {
    HeroSection(snapshot: .preview(thisWeek: 1_200_000_000, lastWeek: 1_600_000_000), clearedBytes: DashboardSnapshot.preview.totalCleared)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock(startingAt: .batch))
}

#Preview("Nothing last week") {
    HeroSection(snapshot: .preview(thisWeek: 1_200_000_000, lastWeek: 0), clearedBytes: DashboardSnapshot.preview.totalCleared)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock(startingAt: .batch))
}

#Preview("Large text") {
    ScrollView {
        HeroSection(snapshot: .preview, clearedBytes: DashboardSnapshot.preview.totalCleared)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock(startingAt: .batch))
    .dynamicTypeSize(.accessibility5)
}

#Preview("First cleanup") {
    HeroSection(snapshot: .preview, clearedBytes: 0)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock())
}

#Preview("Loading") {
    HeroSection(snapshot: .placeholder(), isLoading: true, clearedBytes: 2_000_000_000)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock())
}
#endif
