import SwiftUI

/// The pile on the dashboard, drawn as a bin. With a free limit the bin fills up against it; with no
/// limit, the first few photos in it peek out over the rim. Brick throughout: it's what will be deleted.
/// Empty, it says so quietly instead of disappearing. Wrap it in the link to the pile; it draws no chevron
/// of its own when empty, since there's nothing to open.
struct BinCard: View {
    let count: Int
    /// The pile's real size, as shown.
    let bytes: Int64
    /// The free limit, with what counts toward it. Nil when unlocked: no limit, so the stack shows instead.
    var limit: (counted: Int64, bytes: Int64)?
    /// The first few photos in the pile, for the stack. Only the first `DS.Bin.stackCount` show.
    var thumbnails: [ImageReference] = []

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEmpty: Bool { count == 0 }
    private var fill: Double {
        guard let limit else { return 0 }
        return min(1, Double(limit.counted) / Double(max(limit.bytes, 1)))
    }
    private var isFull: Bool { limit.map { $0.counted >= $0.bytes } ?? false }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Spacing.m))
        layout {
            BinGlyph(fill: fill, thumbnails: limit == nil ? Array(thumbnails.prefix(DS.Bin.stackCount)) : [])
                .animation(reduceMotion ? nil : DS.Motion.calm, value: fill)
            text
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isEmpty, !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous)
                .fill(DS.Palette.card)
                .softShadow()
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text("Bin")
                .font(.headline)
                .foregroundStyle(DS.Palette.ink)
            if isEmpty {
                Text("Empty. What you swipe away collects here.")
                    .font(.callout)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(Format.count(count)) to clear · \(Format.size(bytes))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.brick)
                    .contentTransition(.numericText(value: Double(bytes)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let limit, !isEmpty {
                Text(isFull ? "Full at \(Format.limit(limit.bytes)). Delete these to keep clearing."
                    : "\(Format.size(bytes)) of \(Format.limit(limit.bytes))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessibilityText: String {
        guard !isEmpty else { return "Bin, empty" }
        var parts = ["Bin", "\(Format.count(count)) \(count == 1 ? "photo" : "photos") to clear", Format.size(bytes)]
        if let limit { parts.append(isFull ? "full" : "\(Format.percent(fill)) of \(Format.limit(limit.bytes))") }
        return parts.joined(separator: ", ")
    }
}

/// A bin: a tapered body under a rim. Brick fills it from the bottom by `fill`; `thumbnails` fan out
/// over the rim, their lower halves hidden behind the body, as if dropped in.
private struct BinGlyph: View {
    let fill: Double
    let thumbnails: [ImageReference]

    @ScaledMetric(relativeTo: .title) private var width = DS.Bin.width
    @ScaledMetric(relativeTo: .title) private var height = DS.Bin.height
    @ScaledMetric(relativeTo: .title) private var thumb = DS.Bin.thumbSize

    var body: some View {
        ZStack(alignment: .bottom) {
            stack
            ZStack(alignment: .bottom) {
                BinShape().fill(DS.Palette.brickTint)
                DS.Palette.brick
                    .frame(height: height * fill)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(BinShape())
                BinShape().stroke(DS.Palette.brick, lineWidth: DS.Bin.lineWidth)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(DS.Palette.brick)
                    .frame(width: width + DS.Bin.rimOverhang * 2, height: DS.Bin.rimHeight)
                    .offset(y: -DS.Bin.rimHeight / 2)
            }
        }
        // Room above the rim for the stack, so it never overlaps the text beside it.
        .frame(width: width + DS.Bin.rimOverhang * 2, height: height + (thumbnails.isEmpty ? DS.Bin.rimHeight : thumb * DS.Bin.stackRise))
        .accessibilityHidden(true)
    }

    /// The photos fan out from the middle: the first on top, the rest tilted to either side behind it.
    private var stack: some View {
        ZStack {
            ForEach(Array(thumbnails.enumerated().reversed()), id: \.offset) { offset, reference in
                let side = offset == 0 ? 0 : (offset.isMultiple(of: 2) ? 1.0 : -1.0)
                ItemImage(reference)
                    .frame(width: thumb, height: thumb)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Bin.thumbRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Bin.thumbRadius, style: .continuous)
                            .stroke(DS.Palette.card, lineWidth: DS.Bin.lineWidth)
                    }
                    .rotationEffect(.degrees(side * DS.Bin.fanAngle))
                    .offset(x: side * thumb * DS.Bin.fanSpread)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A bin's body: wider at the top, gently rounded at the bottom corners.
private struct BinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * DS.Bin.taper
        let radius = min(rect.width, rect.height) * DS.Bin.cornerFraction
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX - inset, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX + inset, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}

#if DEBUG
private let previewThumbs = MockImages.photos.prefix(3).map(ImageReference.bundled)

#Preview("Free") {
    VStack(spacing: DS.Spacing.m) {
        BinCard(count: 0, bytes: 0, limit: (0, 2_000_000_000))
        BinCard(count: 41, bytes: 900_000_000, limit: (900_000_000, 2_000_000_000))
        BinCard(count: 96, bytes: 1_850_000_000, limit: (1_850_000_000, 2_000_000_000))
        BinCard(count: 104, bytes: 2_010_000_000, limit: (2_010_000_000, 2_000_000_000))
    }
    .padding(DS.Spacing.l)
    .background(DS.Palette.paper)
}

#Preview("Unlocked") {
    VStack(spacing: DS.Spacing.m) {
        BinCard(count: 0, bytes: 0)
        BinCard(count: 1, bytes: 3_400_000, thumbnails: Array(previewThumbs.prefix(1)))
        BinCard(count: 214, bytes: 4_300_000_000, thumbnails: previewThumbs)
    }
    .padding(DS.Spacing.l)
    .background(DS.Palette.paper)
}

#Preview("Large text") {
    ScrollView {
        VStack(spacing: DS.Spacing.m) {
            BinCard(count: 96, bytes: 1_850_000_000, limit: (1_850_000_000, 2_000_000_000))
            BinCard(count: 214, bytes: 4_300_000_000, thumbnails: previewThumbs)
        }
        .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .dynamicTypeSize(.accessibility5)
}
#endif
