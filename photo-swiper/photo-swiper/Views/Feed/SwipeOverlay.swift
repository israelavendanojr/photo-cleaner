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
            SwipeStamp(kind: .delete, text: label(.left))
                .opacity(left)
            SwipeStamp(kind: .keep, text: label(.right))
                .opacity(right)
            SwipeStamp(kind: .later, text: label(.up))
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
