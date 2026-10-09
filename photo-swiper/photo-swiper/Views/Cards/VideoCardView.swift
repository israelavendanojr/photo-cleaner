import SwiftUI

/// A video still with duration and a prominent file size. Large videos are the biggest wins.
struct VideoCardView: View {
    let item: LibraryItem
    var onPlay: () -> Void = {}

    var body: some View {
        ItemImage(item.image)
            .overlay { BottomScrim() }
            .overlay { playButton }
            .overlay(alignment: .topLeading) {
                if let duration = item.duration {
                    Chip(text: "Video · \(Format.duration(duration))", style: .frosted)
                        .padding(18)
                }
            }
            .overlay(alignment: .bottomLeading) { caption }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .cardShadow()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAction(named: "Play video", onPlay)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: "play.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .offset(x: 3)
                .frame(width: 80, height: 80)
                .background {
                    Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Play video")
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
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private var accessibilityText: String {
        let length = item.duration.map { Format.duration($0) } ?? ""
        return [
            "Video", length, Format.size(item.bytes), Format.day(item.date), item.location,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}

#Preview {
    VideoCardView(item: PreviewSamples.video)
        .padding(14)
        .background(DS.Palette.paper)
}
