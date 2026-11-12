import Charts
import SwiftUI

/// A few facts about the library from when things were taken: the busiest month, how far back the
/// unreviewed photos go, and how many were taken each year.
struct InsightsSection: View {
    let insights: DashboardSnapshot.Insights

    @ScaledMetric(relativeTo: .body) private var yearsHeight = DS.Chart.compactHeight

    var body: some View {
        DashboardCard("About your library") {
            VStack(alignment: .leading, spacing: 0) {
                if let month = insights.busiestMonth {
                    fact("Busiest month", value: Format.month(month),
                         detail: "\(Format.count(insights.busiestMonthCount)) \(insights.busiestMonthCount == 1 ? "photo or video" : "photos and videos") taken")
                    Divider().overlay(DS.Palette.line)
                }
                if let year = insights.oldestUnreviewedYear {
                    fact("Oldest not yet reviewed", value: String(year), detail: "Your unreviewed photos go back this far")
                    Divider().overlay(DS.Palette.line)
                }
                if !insights.perYear.isEmpty {
                    perYear
                        .padding(.top, DS.Spacing.s)
                }
            }
        }
    }

    private func fact(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.ink)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.ink)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var perYear: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Photos and videos per year")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.ink)
            Chart(insights.perYear) { year in
                BarMark(x: .value("Year", String(year.year)), y: .value("Taken", year.count))
                    .foregroundStyle(DS.Palette.ink)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Chart.barCornerRadius,
                                                      topTrailingRadius: DS.Chart.barCornerRadius, style: .continuous))
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(DS.Palette.line)
                    AxisValueLabel {
                        if let count = value.as(Int.self) { Text(Format.count(count)) }
                    }
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(collisionResolution: .greedy)
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.secondary)
                }
            }
            .frame(height: yearsHeight)
            .accessibilityLabel("Photos and videos per year")
            .accessibilityValue(insights.perYear.map { "\($0.year): \(Format.count($0.count))" }.joined(separator: ", "))
            .accessibilityChartDescriptor(YearsDescriptor(years: insights.perYear))
        }
    }
}

/// Audio Graphs for the per-year bars.
private struct YearsDescriptor: AXChartDescriptorRepresentable {
    let years: [DashboardSnapshot.YearCount]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Year", categoryOrder: years.map { String($0.year) })
        let top = Double(years.map(\.count).max() ?? 1)
        let yAxis = AXNumericDataAxisDescriptor(title: "Taken", range: 0...max(top, 1), gridlinePositions: []) {
            Format.count(Int($0))
        }
        let series = AXDataSeriesDescriptor(name: "Photos and videos", isContinuous: false,
                                            dataPoints: years.map { AXDataPoint(x: String($0.year), y: Double($0.count)) })
        return AXChartDescriptor(title: "Photos and videos per year", summary: nil, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}

#if DEBUG
#Preview {
    ScrollView {
        InsightsSection(insights: DashboardSnapshot.preview.insights!)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
}

#Preview("Large text") {
    ScrollView {
        InsightsSection(insights: DashboardSnapshot.preview.insights!)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .dynamicTypeSize(.xxLarge)
}
#endif
