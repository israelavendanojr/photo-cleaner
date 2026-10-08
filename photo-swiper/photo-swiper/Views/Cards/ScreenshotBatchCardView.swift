import SwiftUI

/// A batch of low-value items (screenshots, forwards) decided all at once.
struct ScreenshotBatchCardView: View {
    let batch: ItemBatch

    private var totalBytes: Int64 { batch.items.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Chip(text: batch.label)
            Text(batch.title)
                .dsSerif(34, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: 280, alignment: .leading)
                .padding(.top, DS.Spacing.s)
            Text("\(Format.range(batch.items.map(\.date))) · \(Format.size(totalBytes))")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.xs)
            FannedThumbnails(items: Array(batch.items.prefix(5)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            HStack {
                Text("\(Image(systemName: "arrow.left")) Clear all \(batch.items.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.brick)
                Spacer(minLength: DS.Spacing.xs)
                Text("Right keeps all")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(22)
        .background(DS.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .cardShadow()
        .accessibilityElement(children: .combine)
    }
}

/// A hand of up to five tiles that fans out when it appears.
private struct FannedThumbnails: View {
    let items: [LibraryItem]
    @State private var isFanned = false

    private let tile = CGSize(width: 130, height: 230)
    private let spread: CGFloat = 52

    var body: some View {
        GeometryReader { proxy in
            let fullWidth = tile.width + spread * CGFloat(max(items.count - 1, 0)) + 40
            let scale = min(1, proxy.size.height / (tile.height + 40), proxy.size.width / fullWidth)
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let centered = CGFloat(index) - CGFloat(items.count - 1) / 2
                    ItemImage(item.image)
                        .frame(width: tile.width, height: tile.height)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                        .shadow(color: DS.Palette.shadow.opacity(0.14), radius: 14, y: 10)
                        .rotationEffect(.degrees(isFanned ? Double(centered) * 4 - 2 : 0))
                        .offset(x: isFanned ? centered * spread : 0)
                        .animation(DS.Motion.gentle.delay(0.1 + Double(index) * 0.05), value: isFanned)
                }
            }
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { isFanned = true }
    }
}

#Preview {
    ScreenshotBatchCardView(batch: PreviewSamples.screenshotBatch)
        .frame(height: 600)
        .padding(14)
        .background(DS.Palette.paper)
}
