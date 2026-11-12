import Charts
import SwiftUI

/// How the library has grown, month by month, with a dashed line for the next year at the recent pace,
/// then how full the device is and when it would fill at that pace.
struct StorageTimelineSection: View {
    let timeline: [DashboardSnapshot.MonthPoint]
    let forecast: DashboardSnapshot.Forecast?

    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .body) private var plotHeight = DS.Chart.height
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How many months ahead the dashed line reaches.
    static let projectedMonths = 12
    private static let daysPerMonth = 30.44

    var body: some View {
        DashboardCard("Your library over time") {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                readout
                chart
                    .frame(height: plotHeight)
                if let forecast {
                    StorageBar(forecast: forecast)
                        .padding(.top, DS.Spacing.xs)
                    Text(forecastText(forecast))
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: selected?.date) { _, date in
            if date != nil { Haptics.scrub() }
        }
    }

    // MARK: Data

    private var selected: DashboardSnapshot.MonthPoint? {
        guard let selectedDate else { return nil }
        return timeline.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    /// From the last measured month, `projectedMonths` ahead at the recent pace. Empty with no pace.
    private var projection: [DashboardSnapshot.MonthPoint] {
        guard let last = timeline.last, let pace = forecast?.bytesPerDay, pace > 0 else { return [] }
        return (0...Self.projectedMonths).compactMap { ahead in
            Calendar.current.date(byAdding: .month, value: ahead, to: last.date).map {
                DashboardSnapshot.MonthPoint(date: $0, total: last.total + Int64(pace * Self.daysPerMonth * Double(ahead)))
            }
        }
    }

    private func forecastText(_ forecast: DashboardSnapshot.Forecast) -> String {
        guard let days = forecast.daysUntilFull else {
            return "No new photos or videos lately, so this iPhone isn't filling up with them."
        }
        return "At your recent pace of new photos and videos, about \(Format.size(Int64(forecast.bytesPerDay * Self.daysPerMonth))) a month, "
            + "this iPhone is full in \(Format.untilFull(days: days)). Other apps count too."
    }

    // MARK: Views

    private var readout: some View {
        let point = selected ?? timeline.last
        return VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(Format.size(point?.total ?? 0))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText(value: Double(point?.total ?? 0)))
            Text(selected.map { "By the end of \(Format.month($0.date))" } ?? "Photos and videos now")
                .font(.footnote)
                .foregroundStyle(DS.Palette.ink)
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: point)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        Chart {
            ForEach(timeline) { point in
                AreaMark(x: .value("Month", point.date, unit: .month), y: .value("Size", Double(point.total)))
                    .foregroundStyle(DS.Palette.muted)
                LineMark(x: .value("Month", point.date, unit: .month), y: .value("Size", Double(point.total)),
                         series: .value("Series", "Measured"))
                    .foregroundStyle(DS.Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: DS.Chart.lineWidth, lineCap: .round, lineJoin: .round))
            }
            ForEach(projection) { point in
                LineMark(x: .value("Month", point.date, unit: .month), y: .value("Size", Double(point.total)),
                         series: .value("Series", "Projected"))
                    .foregroundStyle(DS.Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: DS.Chart.lineWidth, lineCap: .round, dash: DS.Chart.projectionDash))
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date, unit: .month))
                    .foregroundStyle(DS.Palette.secondary)
                    .lineStyle(StrokeStyle(lineWidth: DS.Chart.ruleWidth))
                PointMark(x: .value("Month", selected.date, unit: .month), y: .value("Size", Double(selected.total)))
                    .foregroundStyle(DS.Palette.ink)
                    .symbolSize(DS.Chart.pointSize)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(DS.Palette.line)
                AxisValueLabel {
                    if let bytes = value.as(Double.self) { Text(Format.size(Int64(bytes))) }
                }
                .font(.caption2)
                .foregroundStyle(DS.Palette.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel(collisionResolution: .greedy) {
                    if let date = value.as(Date.self) { Text(Format.year(date)) }
                }
                .font(.caption2)
                .foregroundStyle(DS.Palette.secondary)
            }
        }
        .accessibilityLabel("Library size by month, with the next year projected")
        .accessibilityChartDescriptor(TimelineDescriptor(timeline: timeline, projectedEnd: projection.last))
    }
}

/// Photos, everything else, and what's free, as one bar with a line of labels under it.
private struct StorageBar: View {
    let forecast: DashboardSnapshot.Forecast
    @ScaledMetric(relativeTo: .body) private var height = DS.Chart.stackedBarHeight

    private var other: Int64 { max(0, forecast.total - forecast.available - forecast.libraryBytes) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            GeometryReader { proxy in
                let total = Double(max(forecast.total, 1))
                let gaps = DS.Chart.segmentGap * 2
                let width = max(0, proxy.size.width - gaps)
                HStack(spacing: 0) {
                    segment(DS.Palette.ink, width * Double(forecast.libraryBytes) / total)
                    Spacer().frame(width: DS.Chart.segmentGap)
                    segment(DS.Palette.ink.opacity(DS.Chart.categoryOpacities[2]), width * Double(other) / total)
                    Spacer().frame(width: DS.Chart.segmentGap)
                    segment(DS.Palette.line, width * Double(forecast.available) / total)
                }
            }
            .frame(height: height)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            Text("\(Format.size(forecast.libraryBytes)) photos · \(Format.size(other)) other · \(Format.size(forecast.available)) free")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage")
        .accessibilityValue("\(Format.size(forecast.libraryBytes)) photos and videos, \(Format.size(other)) other, \(Format.size(forecast.available)) free of \(Format.size(forecast.total))")
    }

    private func segment(_ color: Color, _ width: Double) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }
}

/// Audio Graphs for the timeline.
private struct TimelineDescriptor: AXChartDescriptorRepresentable {
    let timeline: [DashboardSnapshot.MonthPoint]
    let projectedEnd: DashboardSnapshot.MonthPoint?

    func makeChartDescriptor() -> AXChartDescriptor {
        let first = timeline.first?.date.timeIntervalSince1970 ?? 0
        let last = timeline.last?.date.timeIntervalSince1970 ?? 1
        let xAxis = AXNumericDataAxisDescriptor(title: "Month", range: first...max(last, first + 1), gridlinePositions: []) {
            Format.month(Date(timeIntervalSince1970: $0))
        }
        let top = Double(timeline.map(\.total).max() ?? 1)
        let yAxis = AXNumericDataAxisDescriptor(title: "Library size", range: 0...max(top, 1), gridlinePositions: []) {
            Format.size(Int64($0))
        }
        let series = AXDataSeriesDescriptor(name: "Library size", isContinuous: true,
                                            dataPoints: timeline.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: Double($0.total)) })
        return AXChartDescriptor(title: "Library size by month", summary: summary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }

    private var summary: String {
        guard let first = timeline.first, let last = timeline.last else { return "No photos yet" }
        var text = "From \(Format.size(first.total)) in \(Format.month(first.date)) to \(Format.size(last.total)) now"
        if let projectedEnd { text += ", about \(Format.size(projectedEnd.total)) in a year at the recent pace" }
        return text
    }
}

#if DEBUG
#Preview {
    ScrollView {
        StorageTimelineSection(timeline: DashboardSnapshot.preview.timeline ?? [], forecast: DashboardSnapshot.preview.forecast)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
}

#Preview("Large text") {
    ScrollView {
        StorageTimelineSection(timeline: DashboardSnapshot.preview.timeline ?? [], forecast: DashboardSnapshot.preview.forecast)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .dynamicTypeSize(.xxLarge)
}
#endif
