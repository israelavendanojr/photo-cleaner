import SwiftUI

/// The dashboard's Top Categories (JUN-88): the few kinds of thing taking the most space that are worth
/// a look, biggest first (`DashboardSnapshot.topCategories`), as many as Admin Tools says. A row opens the
/// feed on just that kind. While the section is locked for the plan, only the first few rows do
/// (`TopCategoriesLimits.opensFeed`) and the rest open the paywall; off, the section isn't shown. There's
/// no total: the kinds overlap (a blurry shot can also be a similar one), so their sizes don't add up.
///
/// A row's ticks show its size against the biggest. The first time the rows are seen each launch, they
/// fade up one after another; `entered` says they have.
struct LibraryList: View {
    @Environment(FeedViewModel.self) private var vm
    /// The dashboard's numbers, or a stand-in while they load.
    let snapshot: DashboardSnapshot
    var isLoading = false
    /// False until the rows' entrance should play.
    var entered = true

    private var access: FeatureAccess { vm.featureAccess(.topCategories) }
    private var rows: [DashboardSnapshot.Row] { snapshot.topCategories(count: vm.topCategories.limits.count) }

    var body: some View {
        if access.isVisible {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                header
                if rows.isEmpty {
                    Text(snapshot.scanPercent == nil
                        ? "Nothing obvious left to clear."
                        : "Still looking through your library. Suggestions show up as it's analyzed.")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let largest = rows.map(\.bytes).max() ?? 0
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                            VStack(spacing: 0) {
                                Rule()
                                button(row, at: offset, share: largest > 0 ? Double(row.bytes) / Double(largest) : 0)
                            }
                            .modifier(RowEntrance(entered: entered, index: offset))
                        }
                        Rule()
                    }
                    .redacted(reason: isLoading ? .placeholder : [])
                }
            }
            .disabled(isLoading)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text("Top Categories")
                .dsSerif(22, relativeTo: .title3, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let percent = snapshot.scanPercent, !isLoading {
                status(percent)
            }
        }
    }

    /// "Analyzing · 86%" while the index is still building, so the numbers read as a floor.
    private func status(_ percent: Int) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            if vm.isDashboardRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(DS.Palette.secondary)
            }
            Text("Analyzing · \(Format.percent(Double(percent) / 100))")
                .monospacedDigit()
        }
        .font(.footnote)
        .foregroundStyle(DS.Palette.secondary)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    /// Opens the feed on the row's kind, or the paywall for a row past the free ones while locked.
    private func button(_ row: DashboardSnapshot.Row, at index: Int, share: Double) -> some View {
        let opensFeed = vm.topCategories.limits.opensFeed(rowAt: index, access: access)
        return Button {
            Haptics.advance()
            if opensFeed {
                vm.focusFeed(on: row.focus)
            } else {
                vm.requestUnlock(.topCategories)
            }
        } label: {
            TallyRow(title: row.focus.title, count: row.count, share: share, bytes: row.bytes)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.focus.title)
                .accessibilityValue("\(row.focus.count(row.count)), \(Format.size(row.bytes))")
        }
        .buttonStyle(.plain)
        .accessibilityHint(opensFeed ? "Shows only \(row.focus.phrase) in the feed" : "Unlock to show only \(row.focus.phrase)")
        .accessibilityIdentifier("library.row.\(row.focus.identifier)")
    }
}

/// A row fading up into place, later rows a beat after earlier ones. Still under Reduce Motion.
private struct RowEntrance: ViewModifier {
    let entered: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : DS.Spacing.xs)
            .animation(reduceMotion ? nil : DS.Motion.calm.delay(Double(index) * DS.Motion.rowStagger), value: entered)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        LibraryList(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .paperBackground()
    .environment(FeedViewModel.mock())
}

#Preview("Dark") {
    ScrollView {
        LibraryList(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .paperBackground()
    .environment(FeedViewModel.mock())
    .preferredColorScheme(.dark)
}

#Preview("Loading") {
    LibraryList(snapshot: .placeholder(), isLoading: true)
        .padding(DS.Spacing.l)
        .paperBackground()
        .environment(FeedViewModel.mock())
}

#Preview("Large text") {
    ScrollView {
        LibraryList(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .paperBackground()
    .environment(FeedViewModel.mock())
    .dynamicTypeSize(.accessibility2)
}
#endif
