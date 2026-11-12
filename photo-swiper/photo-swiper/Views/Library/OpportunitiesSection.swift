import SwiftUI

/// What's left to clear, biggest first. Each row opens the feed on just that kind.
struct OpportunitiesSection: View {
    @Environment(FeedViewModel.self) private var vm
    let snapshot: DashboardSnapshot

    var body: some View {
        DashboardCard("Worth a look") {
            if snapshot.opportunities.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.opportunities.enumerated()), id: \.element.id) { offset, opportunity in
                        if offset > 0 { Divider().overlay(DS.Palette.line) }
                        row(opportunity)
                    }
                }
            }
        } accessory: {
            status
        }
    }

    private var emptyText: String {
        snapshot.health == nil
            ? "Still looking through your library. Suggestions show up as it's analyzed."
            : "Nothing obvious left to clear."
    }

    /// "Analyzing · 86%" while the index is still building, otherwise when the numbers were worked out.
    private var status: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: DS.Spacing.xxs) {
                if vm.isDashboardRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DS.Palette.secondary)
                }
                Text(statusText(now: context.date))
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(DS.Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusText(now: Date) -> String {
        if let percent = snapshot.scanPercent { return "Analyzing · \(Format.percent(Double(percent) / 100))" }
        return "Updated \(Format.relative(snapshot.computedAt, now: now))"
    }

    private func row(_ opportunity: DashboardSnapshot.Opportunity) -> some View {
        Button {
            Haptics.advance()
            vm.focusFeed(on: opportunity.category)
        } label: {
            OpportunityRow(opportunity: opportunity, share: share(of: opportunity))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows only \(opportunity.category.title.lowercased()) in the feed")
        .accessibilityIdentifier("library.opportunity.\(opportunity.category.rawValue)")
    }

    /// Against the biggest, so the bars rank at a glance.
    private func share(of opportunity: DashboardSnapshot.Opportunity) -> Double {
        guard let top = snapshot.opportunities.first?.bytes, top > 0 else { return 0 }
        return Double(opportunity.bytes) / Double(top)
    }
}

private struct OpportunityRow: View {
    let opportunity: DashboardSnapshot.Opportunity
    /// 0...1 of the biggest row.
    let share: Double

    @ScaledMetric(relativeTo: .body) private var iconWidth = 28
    /// Room for a four-digit count, so every row's bar ends at the same place and the bars compare.
    @ScaledMetric(relativeTo: .footnote) private var countWidth = 44

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            // At accessibility sizes the icon column would squeeze the title to a letter a line.
            if !typeSize.isAccessibilitySize {
                Image(systemName: opportunity.category.systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if typeSize.isAccessibilitySize {
                    title
                    size
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                        title
                        Spacer(minLength: DS.Spacing.xs)
                        size
                    }
                }
                HStack(spacing: DS.Spacing.s) {
                    ProgressLine(value: share, tint: DS.Palette.brick)
                        .accessibilityHidden(true)
                    Text(Format.count(opportunity.count))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                        .frame(minWidth: typeSize.isAccessibilitySize ? nil : countWidth, alignment: .trailing)
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DS.Spacing.s)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(opportunity.category.title)
        .accessibilityValue("\(Format.count(opportunity.count)) items, \(Format.size(opportunity.bytes))")
        .accessibilityAddTraits(.isButton)
    }

    private var title: some View {
        Text(opportunity.category.title)
            .font(.body)
            .foregroundStyle(DS.Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var size: some View {
        Text(Format.size(opportunity.bytes))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(DS.Palette.brick)
            .contentTransition(.numericText(value: Double(opportunity.bytes)))
    }
}

#if DEBUG
#Preview {
    ScrollView {
        OpportunitiesSection(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock())
}

#Preview("Large text") {
    ScrollView {
        OpportunitiesSection(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock())
    .dynamicTypeSize(.xxLarge)
}
#endif
