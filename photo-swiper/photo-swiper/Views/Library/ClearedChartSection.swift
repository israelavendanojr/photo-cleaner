import Charts
import SwiftUI

/// Space cleared over time: the running total, or week by week. Drag across it to read a point.
struct ClearedChartSection: View {
    enum Mode: String, CaseIterable, Identifiable {
        case total = "Total"
        case weekly = "Weekly"
        var id: Self { self }
    }

    let snapshot: DashboardSnapshot

    @State private var mode = Mode.total
    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .body) private var plotHeight = DS.Chart.height
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DashboardCard("Cleared over time") {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                readout
                chart
                    .frame(height: plotHeight)
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("library.chartMode")
            }
        }
        .onChange(of: mode) { selectedDate = nil }
        .onChange(of: selected?.date) { _, date in
            if date != nil { Haptics.scrub() }
        }
    }

    // MARK: Data

    /// One plotted value: a day's running total, or a week's amount.
    struct Point: Identifiable, Equatable {
        let date: Date
        let bytes: Int64
        var id: Date { date }
    }

    private var points: [Point] {
        switch mode {
        case .total: snapshot.cumulative.map { Point(date: $0.date, bytes: $0.total) }
        case .weekly: snapshot.weekly.map { Point(date: $0.date, bytes: $0.bytes) }
        }
    }

    /// The point nearest where the finger is.
    private var selected: Point? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    // MARK: Views

    /// The scrubbed point, or the latest one: the number the chart is about.
    private var readout: some View {
        let point = selected ?? points.last
        return VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(Format.size(point?.bytes ?? 0))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText(value: Double(point?.bytes ?? 0)))
            Text(caption(for: point))
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: point)
        .accessibilityElement(children: .combine)
    }

    private func caption(for point: Point?) -> String {
        guard let point else { return "" }
        switch mode {
        case .total: return selected == nil ? "In total" : "By \(Format.shortDay(point.date))"
        case .weekly: return selected == nil ? "This week" : "Week of \(Format.shortDay(point.date))"
        }
    }

    private var chart: some View {
        Chart {
            switch mode {
            case .total:
                ForEach(points) { point in
                    AreaMark(x: .value("Day", point.date, unit: .day), y: .value("Cleared", Double(point.bytes)))
                        .foregroundStyle(DS.Palette.brickTint)
                        .interpolationMethod(.stepEnd)
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Cleared", Double(point.bytes)))
                        .foregroundStyle(DS.Palette.brick)
                        .lineStyle(StrokeStyle(lineWidth: DS.Chart.lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.stepEnd)
                }
            case .weekly:
                ForEach(points) { point in
                    BarMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Cleared", Double(point.bytes)))
                        .foregroundStyle(DS.Palette.brick.opacity(selected == nil || selected == point ? 1 : 0.35))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Chart.barCornerRadius,
                                                          topTrailingRadius: DS.Chart.barCornerRadius, style: .continuous))
                }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date, unit: mode == .total ? .day : .weekOfYear))
                    .foregroundStyle(DS.Palette.secondary)
                    .lineStyle(StrokeStyle(lineWidth: DS.Chart.ruleWidth))
                if mode == .total {
                    PointMark(x: .value("Day", selected.date, unit: .day), y: .value("Cleared", Double(selected.bytes)))
                        .foregroundStyle(DS.Palette.brick)
                        .symbolSize(DS.Chart.pointSize)
                }
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
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.secondary)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: mode)
        .accessibilityLabel(mode == .total ? "Space cleared in total" : "Space cleared each week")
        .accessibilityChartDescriptor(ClearedChartDescriptor(points: points, mode: mode))
    }
}

/// Audio Graphs and the VoiceOver chart summary.
private struct ClearedChartDescriptor: AXChartDescriptorRepresentable {
    let points: [ClearedChartSection.Point]
    let mode: ClearedChartSection.Mode

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date)
        let maxBytes = Double(points.map(\.bytes).max() ?? 0)
        let xAxis = AXNumericDataAxisDescriptor(
            title: mode == .total ? "Day" : "Week",
            range: (dates.first?.timeIntervalSince1970 ?? 0)...(dates.last?.timeIntervalSince1970 ?? 1),
            gridlinePositions: []
        ) { Format.shortDay(Date(timeIntervalSince1970: $0)) }
        let yAxis = AXNumericDataAxisDescriptor(title: "Cleared", range: 0...max(maxBytes, 1), gridlinePositions: []) {
            Format.size(Int64($0))
        }
        let series = AXDataSeriesDescriptor(
            name: mode == .total ? "Total cleared" : "Cleared that week",
            isContinuous: mode == .total,
            dataPoints: points.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: Double($0.bytes)) }
        )
        return AXChartDescriptor(title: mode == .total ? "Space cleared in total" : "Space cleared each week",
                                 summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "Nothing cleared yet" }
        switch mode {
        case .total:
            return "\(Format.size(last.bytes)) cleared since \(Format.shortDay(first.date))"
        case .weekly:
            let best = points.max { $0.bytes < $1.bytes }
            return "Most in the week of \(Format.shortDay(best?.date ?? first.date)): \(Format.size(best?.bytes ?? 0))"
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        ClearedChartSection(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
}

#Preview("Large text") {
    ScrollView {
        ClearedChartSection(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .dynamicTypeSize(.xxLarge)
}
#endif
