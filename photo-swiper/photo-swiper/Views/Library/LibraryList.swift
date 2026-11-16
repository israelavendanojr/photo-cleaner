import SwiftUI

/// The dashboard's two ruled lists. "Ready to clear" is what clearing would free, by kind, biggest first,
/// with what it comes to; "Also in your library" is the library's own kinds and what's saved for later.
/// A row opens the feed on just that kind, and that's all it does.
///
/// A row's ticks show its size against the biggest in its list. The first time the lists are seen each
/// launch, their rows fade up one after another; `entered` says they have.
struct LibraryList: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The dashboard's numbers, or a stand-in while they load.
    let snapshot: DashboardSnapshot
    var isLoading = false
    /// False until the rows' entrance should play.
    var entered = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            section(
                "Ready to clear", rows: snapshot.toClearRows, tint: DS.Palette.brick, total: snapshot.toClearBytes, firstIndex: 0
            ) {
                Text(snapshot.scanPercent == nil
                    ? "Nothing obvious left to clear."
                    : "Still looking through your library. Suggestions show up as it's analyzed.")
                    .font(.callout)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !snapshot.otherRows.isEmpty {
                section(
                    "Also in your library", rows: snapshot.otherRows, tint: DS.Palette.ink, total: nil,
                    firstIndex: snapshot.toClearRows.count
                ) { EmptyView() }
            }
        }
        .disabled(isLoading)
    }

    private func section(
        _ title: String, rows: [DashboardSnapshot.Row], tint: Color, total: Int64?, firstIndex: Int,
        @ViewBuilder empty: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            header(title, total: rows.isEmpty ? nil : total, showsStatus: firstIndex == 0)
            if rows.isEmpty {
                empty()
            } else {
                let largest = rows.map(\.bytes).max() ?? 0
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                        VStack(spacing: 0) {
                            Rule()
                            button(row, share: largest > 0 ? Double(row.bytes) / Double(largest) : 0, tint: tint)
                        }
                        .modifier(RowEntrance(entered: entered, index: firstIndex + offset))
                    }
                    Rule()
                }
                .redacted(reason: isLoading ? .placeholder : [])
            }
        }
    }

    // MARK: Header

    private func header(_ title: String, total: Int64?, showsStatus: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(title)
                    .dsSerif(22, relativeTo: .title3, weight: .medium)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let total, !isLoading {
                    Text(Format.size(total))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.brick)
                        .contentTransition(.numericText(value: Double(total)))
                        .accessibilityLabel("\(Format.size(total)) in all")
                        .accessibilityIdentifier("library.toClearTotal")
                }
            }
            if showsStatus, let percent = snapshot.scanPercent, !isLoading {
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

    private func button(_ row: DashboardSnapshot.Row, share: Double, tint: Color) -> some View {
        Button {
            Haptics.advance()
            vm.focusFeed(on: row.focus)
        } label: {
            TallyRow(title: row.focus.title, count: row.count, share: share, bytes: row.bytes, tint: tint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.focus.title)
                .accessibilityValue("\(row.focus.count(row.count)), \(Format.size(row.bytes))")
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows only \(row.focus.phrase) in the feed")
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
