import SwiftUI

/// When the user cleared space: a grid of the last 16 weeks, a column a week, darker for more cleared,
/// and how many weeks in a row they've cleaned up. No pressure: a missed week just starts a new count.
struct ActivitySection: View {
    let activity: DashboardSnapshot.Activity

    @ScaledMetric(relativeTo: .caption) private var cell = DS.Chart.heatCellSize
    @ScaledMetric(relativeTo: .caption) private var gap = DS.Chart.heatCellGap

    var body: some View {
        DashboardCard("Activity") {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                streak
                // At large text the cells grow past the card; then the grid scrolls inside it, latest week in view.
                ViewThatFits(in: .horizontal) {
                    grid
                    ScrollView(.horizontal) {
                        grid
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cleanups over the last \(DashboardStats.activityWeeks) weeks")
                .accessibilityValue(summary)
                legend
            }
        }
    }

    private var streak: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(activity.streakWeeks > 0 ? "\(Format.count(activity.streakWeeks)) \(activity.streakWeeks == 1 ? "week" : "weeks") in a row" : "Start a streak this week")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText(value: Double(activity.streakWeeks)))
            Text("Cleaned up on \(Format.count(activity.activeDays)) \(activity.activeDays == 1 ? "day" : "days") in the last \(DashboardStats.activityWeeks) weeks")
                .font(.footnote)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
        let most = activity.days.max { $0.bytes < $1.bytes }
        var text = "Cleaned up on \(activity.activeDays) days"
        if let most, most.bytes > 0 { text += ", the most on \(Format.shortDay(most.date)): \(Format.size(most.bytes))" }
        return text
    }

    /// Level 0 is an empty `line` cell; 1 is `brickTint`; 2...4 are brick at `DS.Chart.heatOpacities`.
    static func color(level: Int) -> Color {
        switch level {
        case ...0: DS.Palette.line
        case 1: DS.Palette.brickTint
        default: DS.Palette.brick.opacity(DS.Chart.heatOpacities[min(level, DS.Chart.heatOpacities.count) - 1])
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        ActivitySection(activity: DashboardSnapshot.preview.activity!)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
}

#Preview("Large text") {
    ScrollView {
        ActivitySection(activity: DashboardSnapshot.preview.activity!)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .dynamicTypeSize(.xxLarge)
}
#endif
