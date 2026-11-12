import SwiftUI

/// What the library's space is made of: one bar in ink shades, then a labeled row for each kind, so the
/// shades only separate and the labels say what's what.
struct CompositionSection: View {
    /// Biggest first, as `DashboardStats.composition` orders them.
    let slices: [DashboardSnapshot.Slice]

    @ScaledMetric(relativeTo: .body) private var barHeight = DS.Chart.stackedBarHeight
    @ScaledMetric(relativeTo: .body) private var swatchSize = DS.Chart.swatchSize

    var body: some View {
        DashboardCard("What's taking space") {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                bar
                VStack(spacing: 0) {
                    ForEach(Array(slices.enumerated()), id: \.element.id) { offset, slice in
                        if offset > 0 { Divider().overlay(DS.Palette.line) }
                        row(slice, shade: shade(offset))
                    }
                }
            }
        }
    }

    private func shade(_ offset: Int) -> Color {
        let opacities = DS.Chart.categoryOpacities
        return DS.Palette.ink.opacity(opacities[min(offset, opacities.count - 1)])
    }

    private var bar: some View {
        GeometryReader { proxy in
            let gaps = DS.Chart.segmentGap * Double(max(slices.count - 1, 0))
            let width = max(0, proxy.size.width - gaps)
            HStack(spacing: DS.Chart.segmentGap) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { offset, slice in
                    Rectangle()
                        .fill(shade(offset))
                        .frame(width: width * slice.share)
                }
            }
        }
        .frame(height: barHeight)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func row(_ slice: DashboardSnapshot.Slice, shade: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
            RoundedRectangle(cornerRadius: DS.Chart.heatCellRadius, style: .continuous)
                .fill(shade)
                .frame(width: swatchSize, height: swatchSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(slice.kind.title)
                    .font(.body)
                    .foregroundStyle(DS.Palette.ink)
                Text("\(Format.count(slice.count)) · \(Format.percent(slice.share))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.ink)
            }
            Spacer(minLength: DS.Spacing.xs)
            Text(Format.size(slice.bytes))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText(value: Double(slice.bytes)))
        }
        .padding(.vertical, DS.Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slice.kind.title)
        .accessibilityValue("\(Format.size(slice.bytes)), \(Format.percent(slice.share)) of the library, \(Format.count(slice.count)) items")
    }
}

extension LibraryProfile.Kind {
    /// "Live Photos", as a composition row.
    var title: String {
        switch self {
        case .video: "Videos"
        case .livePhoto: "Live Photos"
        case .screenshot: "Screenshots"
        case .photo: "Other photos"
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        CompositionSection(slices: DashboardSnapshot.preview.composition ?? [])
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
}

#Preview("Large text") {
    ScrollView {
        CompositionSection(slices: DashboardSnapshot.preview.composition ?? [])
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .dynamicTypeSize(.xxLarge)
}
#endif
