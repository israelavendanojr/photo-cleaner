import SwiftUI

/// The Delete / Keep / Later stamps that fade in over a card as it's dragged.
struct SwipeOverlay: View {
    let offset: CGSize
    let label: (SwipeDirection) -> String

    var body: some View {
        let left = ramp(-offset.width)
        let right = ramp(offset.width)
        let up = ramp(-offset.height) * (1 - max(left, right))

        ZStack {
            Stamp(
                wash: DS.Palette.brick.opacity(0.25), disc: DS.Palette.brick, icon: "trash",
                iconColor: .white, text: label(.left), textColor: DS.Palette.brick
            )
            .opacity(left)
            Stamp(
                wash: DS.Palette.ink.opacity(0.1), disc: DS.Palette.ink, icon: "checkmark",
                iconColor: .white, text: label(.right), textColor: DS.Palette.ink
            )
            .opacity(right)
            Stamp(
                wash: DS.Palette.card.opacity(0.3), disc: DS.Palette.card, icon: "arrow.up",
                iconColor: DS.Palette.ink, text: label(.up), textColor: DS.Palette.ink
            )
            .opacity(up)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 0 until 30pt of travel, fully visible by 130pt.
    private func ramp(_ distance: CGFloat) -> Double {
        min(max((distance - 30) / 100, 0), 1)
    }
}

private struct Stamp: View {
    let wash: Color
    let disc: Color
    let icon: String
    let iconColor: Color
    let text: String
    let textColor: Color

    var body: some View {
        wash.overlay {
            VStack(spacing: DS.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 84, height: 84)
                    .background(disc, in: Circle())
                    .cardShadow()
                Text(text)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, DS.Spacing.m)
                    .padding(.vertical, 6)
                    .background(DS.Palette.card, in: Capsule())
            }
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        ForEach([CGSize(width: -140, height: 0), CGSize(width: 140, height: 0), CGSize(width: 0, height: -140)], id: \.width) { offset in
            PhotoCardView(item: PreviewSamples.plainPhoto)
                .overlay { SwipeOverlay(offset: offset) { $0 == .left ? "Delete · 3.4 MB" : $0 == .right ? "Keep" : "Later" } }
        }
    }
    .frame(height: 300)
    .padding()
    .background(DS.Palette.paper)
}
