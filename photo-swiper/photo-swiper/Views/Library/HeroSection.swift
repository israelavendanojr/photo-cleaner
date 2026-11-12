import SwiftUI

/// The top of the dashboard: total space cleared and how much of the library has been reviewed. Before anything is cleared it's an invitation to start instead.
struct HeroSection: View {
    @Environment(FeedViewModel.self) private var vm
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

    private var cleared: some View {
        Text(Format.size(clearedBytes))
            .dsSerif(48, relativeTo: .largeTitle)
            .monospacedDigit()
            .foregroundStyle(DS.Palette.brick)
            .contentTransition(.numericText(value: Double(clearedBytes)))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel("\(Format.size(clearedBytes)) cleared")
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
                Text(Format.percent(vm.libraryReviewedFraction))
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

#Preview("Large text") {
    ScrollView {
        HeroSection(snapshot: .preview, clearedBytes: DashboardSnapshot.preview.totalCleared)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock(startingAt: .batch))
    .dynamicTypeSize(.xxLarge)
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
