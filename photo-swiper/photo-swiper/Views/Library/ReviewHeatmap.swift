import SwiftUI

/// Photos reviewed by day over the last 16 weeks, a column a week, darker for more. Keeping counts as
/// much as clearing: reviewing is the habit it shows. In ink, since it isn't space cleared, and with no
/// streak, so a missed day costs nothing.
struct ReviewHeatmap: View {
    let activity: DashboardSnapshot.Activity

    @ScaledMetric(relativeTo: .caption) private var cell = DS.Chart.heatCellSize
    @ScaledMetric(relativeTo: .caption) private var gap = DS.Chart.heatCellGap

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(caption)
                .font(.footnote)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            // At large text the cells grow past the screen; then the grid scrolls, latest week in view.
            ViewThatFits(in: .horizontal) {
                grid
                ScrollView(.horizontal) {
                    grid
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photos reviewed over the last \(DashboardStats.activityWeeks) weeks")
            .accessibilityValue(summary)
            legend
        }
    }

    private var caption: String {
        let photos = activity.total == 1 ? "photo" : "photos"
        return "\(Format.count(activity.total)) \(photos) reviewed in the last \(DashboardStats.activityWeeks) weeks"
    }

    /// Columns are weeks (oldest first), rows are days of the week from the calendar's first.
    private var weeks: [[DashboardSnapshot.Activity.Day]] {
        stride(from: 0, to: activity.days.count, by: 7).map { Array(activity.days[$0..<min($0 + 7, activity.days.count)]) }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: gap) {
            monthLabels
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(week) { day in
                            RoundedRectangle(cornerRadius: DS.Chart.heatCellRadius, style: .continuous)
                                .fill(Self.color(level: day.level))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    /// Which weeks get a month's name: the first week of each month, unless the last name is under three
    /// columns back, where they'd run together.
    private var labeledWeeks: Set<Int> {
        var labeled: Set<Int> = []
        var last = -3
        for (offset, week) in weeks.enumerated() {
            guard let start = week.first?.date else { continue }
            let isNewMonth = offset == 0 || !Calendar.current.isDate(start, equalTo: weeks[offset - 1].first?.date ?? start, toGranularity: .month)
            guard isNewMonth, offset - last >= 3 else { continue }
            // A first column whose month ends in the next two weeks makes way for the next one.
            if offset == 0, weeks.prefix(3).dropFirst().contains(where: { !Calendar.current.isDate($0.first?.date ?? start, equalTo: start, toGranularity: .month) }) {
                continue
            }
            labeled.insert(offset)
            last = offset
        }
        return labeled
    }

    /// A month's short name over the first week that starts in it.
    private var monthLabels: some View {
        let labeled = labeledWeeks
        return HStack(spacing: gap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { offset, week in
                let start = week.first?.date ?? .now
                Text(labeled.contains(offset) ? Format.shortMonth(start) : "")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize()
                    .frame(width: cell, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: gap) {
            Text("Less")
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: DS.Chart.heatCellRadius, style: .continuous)
                    .fill(Self.color(level: level))
                    .frame(width: cell, height: cell)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(DS.Palette.secondary)
        .accessibilityHidden(true)
    }

    private var summary: String {
        let most = activity.days.max { $0.count < $1.count }
        let days = activity.activeDays == 1 ? "day" : "days"
        var text = "Reviewed on \(Format.count(activity.activeDays)) \(days)"
        if let most, most.count > 0 { text += ", the most on \(Format.shortDay(most.date)): \(Format.count(most.count))" }
        return text
    }

    /// Level 0 is an empty `line` cell; 1...4 are ink at `DS.Chart.heatOpacities`.
    static func color(level: Int) -> Color {
        level <= 0 ? DS.Palette.line : DS.Palette.ink.opacity(DS.Chart.heatOpacities[min(level, DS.Chart.heatOpacities.count) - 1])
    }
}

#if DEBUG
#Preview {
    ReviewHeatmap(activity: DashboardSnapshot.preview.reviews!)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
}

#Preview("Large text") {
    ScrollView {
        ReviewHeatmap(activity: DashboardSnapshot.preview.reviews!)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .dynamicTypeSize(.accessibility5)
}
#endif
