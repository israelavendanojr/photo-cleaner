import SwiftUI

/// A video still with duration and a prominent file size. Large videos are the biggest wins.
/// A Share button sits bottom-trailing when sharing is on (JUN-8); the size scales down to clear it.
struct VideoCardView: View {
    let item: LibraryItem
    var onPlay: () -> Void = {}
    /// The Share button's state; nil shows none.
    var share: ShareButtonState?
    var onShare: () -> Void = {}

    var body: some View {
        ItemImage(item.image)
            .overlay { BottomScrim() }
            .overlay {
                CardCenterButton(accessibilityLabel: "Play video", action: onPlay)
            }
            .overlay(alignment: .topLeading) {
                if let duration = item.duration {
                    Chip(text: Format.duration(duration), style: .frosted)
                        .padding(18)
                }
            }
            .overlay(alignment: .bottomLeading) { caption }
            .cardShareButton(share, action: onShare)
            .rankDebugBadge(for: item)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .cardShadow()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAction(named: "Play video", onPlay)
            .cardShareAction(share, action: onShare)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.size(item.bytes))
                .dsSerif(48, relativeTo: .largeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(Format.day(item.date))
                .dsSerif(20, relativeTo: .title3)
                .padding(.top, 4)
            if let location = item.location {
                Text(location)
                    .font(.subheadline)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 22)
        .padding(.trailing, share == nil ? 22 : CardShareButton.captionClearance)
        .padding(.bottom, 24)
    }

    private var accessibilityText: String {
        let length = item.duration.map { Format.duration($0) } ?? ""
        return [
            "Video", length, Format.size(item.bytes), Format.day(item.date), item.location,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}

#if DEBUG
#Preview {
    VideoCardView(item: PreviewSamples.video)
        .padding(14)
        .paperBackground()
}

#Preview("Share, large text") {
    VideoCardView(item: PreviewSamples.video, share: .ready)
        .padding(14)
        .paperBackground()
        .dynamicTypeSize(.xxLarge)
}
#endif
