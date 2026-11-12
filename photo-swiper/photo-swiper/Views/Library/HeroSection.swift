import SwiftUI

/// The top of the dashboard: total space cleared, this week against last, library health, and how much of
/// the library has been reviewed. Before anything is cleared it's an invitation to start instead.
struct HeroSection: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The dashboard's numbers, or a stand-in while they load.
    let snapshot: DashboardSnapshot
    /// The snapshot is a stand-in: the parts drawn from it are redacted. The rest is live.
    var isLoading = false
    /// Everything cleared. The history's total, or the view model's if a delete just landed before it.
    let clearedBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if clearedBytes > 0 {
                cleared
            } else {
                firstCleanup
            }
            reviewed
                .padding(.top, DS.Spacing.l)
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: clearedBytes)
    }

    /// Side by side, or stacked at accessibility sizes so the number keeps its size.
    private var cleared: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.l))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Spacing.m))
        return layout {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Space cleared")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                Text(Format.size(clearedBytes))
                    .dsSerif(48, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.brick)
                    .contentTransition(.numericText(value: Double(clearedBytes)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                StatDelta(current: snapshot.clearedThisWeek, previous: snapshot.clearedLastWeek)
                    .redacted(reason: isLoading ? .placeholder : [])
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            RingGauge(value: snapshot.health, caption: "Health")
                .redacted(reason: isLoading ? .placeholder : [])
                .accessibilityHint("How little clutter is left, and how much you've reviewed")
        }
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

    private var reviewed: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text("\(Int((vm.libraryReviewedFraction * 100).rounded()))%")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: vm.libraryReviewedFraction))
                Text("reviewed")
                    .font(.callout)
            }
            .foregroundStyle(DS.Palette.ink)
            ProgressLine(value: vm.libraryReviewedFraction, height: 4)
            Text("\(Format.count(vm.libraryReviewedCount)) of \(Format.count(vm.stats.totalItems)) photos reviewed")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    HeroSection(snapshot: .preview, clearedBytes: DashboardSnapshot.preview.totalCleared)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock(startingAt: .batch))
}
#endif
