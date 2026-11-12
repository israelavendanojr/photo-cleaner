import SwiftUI

/// What's worth a look in the library, one row per kind with something in it: biggest first, saved for
/// later last. A row opens the feed on just that kind, and that's all it does.
struct LibraryCard: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The dashboard's numbers, or a stand-in while they load.
    let snapshot: DashboardSnapshot
    var isLoading = false

    private var rows: [DashboardSnapshot.Row] { snapshot.rows ?? [] }

    var body: some View {
        DashboardCard {
            header
        } content: {
            if rows.isEmpty {
                Text(snapshot.scanPercent == nil
                    ? "Nothing obvious left to look at."
                    : "Still looking through your library. Suggestions show up as it's analyzed.")
                    .font(.callout)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                        if offset > 0 { Divider().overlay(DS.Palette.line) }
                        button(row)
                    }
                }
                .redacted(reason: isLoading ? .placeholder : [])
            }
        }
        .disabled(isLoading)
    }

    // MARK: Header

    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DS.Spacing.xs))
        return layout {
            Text("Worth a look")
                .font(.headline)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
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
        .foregroundStyle(DS.Palette.ink)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    private func button(_ row: DashboardSnapshot.Row) -> some View {
        Button {
            Haptics.advance()
            vm.focusFeed(on: row.focus)
        } label: {
            LibraryRow(row: row)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows only \(row.focus.phrase) in the feed")
        .accessibilityIdentifier("library.row.\(row.focus.identifier)")
    }
}

/// Icon, title, "count · size", chevron. The size is brick for what clearing would free (the cleanup
/// categories) and ink for the library's own kinds and what's saved for later, which aren't amounts to clear.
private struct LibraryRow: View {
    let row: DashboardSnapshot.Row

    @ScaledMetric(relativeTo: .body) private var iconWidth = DS.LibraryList.iconWidth
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isToClear: Bool {
        if case .category(let category) = row.focus { category != .photo } else { false }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            // At accessibility sizes the icon column would squeeze the title to a letter a line.
            if !typeSize.isAccessibilitySize {
                Image(systemName: row.focus.systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    title
                    amount
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                title
                Spacer(minLength: DS.Spacing.xs)
                amount
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DS.Spacing.s)
        .frame(minHeight: DS.Tap.minimum)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.focus.title)
        .accessibilityValue("\(row.focus.count(row.count)), \(Format.size(row.bytes))")
        .accessibilityAddTraits(.isButton)
    }

    private var title: some View {
        Text(row.focus.title)
            .font(.body)
            .foregroundStyle(DS.Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "214 · 1.87 GB" on one line; at accessibility sizes the count and size stack, so neither truncates.
    @ViewBuilder private var amount: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                countText(Format.count(row.count))
                sizeText
            }
        } else {
            HStack(spacing: DS.Spacing.xxs) {
                countText("\(Format.count(row.count)) ·")
                sizeText
            }
            .lineLimit(1)
        }
    }

    private func countText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(DS.Palette.ink)
    }

    private var sizeText: some View {
        Text(Format.size(row.bytes))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isToClear ? DS.Palette.brick : DS.Palette.ink)
            .contentTransition(.numericText(value: Double(row.bytes)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        LibraryCard(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock(startingAt: .batch))
}

#Preview("Large text") {
    ScrollView {
        LibraryCard(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock(startingAt: .batch))
    .dynamicTypeSize(.accessibility5)
}

#Preview("Still analyzing, nothing found") {
    var snapshot = DashboardSnapshot.preview
    snapshot.rows = []
    snapshot.scanPercent = 12
    return LibraryCard(snapshot: snapshot)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock())
}

#Preview("Loading") {
    LibraryCard(snapshot: .placeholder(), isLoading: true)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock())
}
#endif
