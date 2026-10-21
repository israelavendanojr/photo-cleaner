import SwiftUI

/// One decision's stamp: a tinted wash with an icon disc and its label. Shown over a dragged
/// card, and in onboarding's demo stack.
struct SwipeStamp: View {
    enum Kind { case delete, keep, later }

    let kind: Kind
    let text: String
    /// A smaller disc and label for thumbnail-sized cards.
    var isCompact = false

    var body: some View {
        let disc: CGFloat = isCompact ? 44 : 84
        wash.overlay {
            VStack(spacing: isCompact ? DS.Spacing.xs : DS.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: disc * 0.43, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: disc, height: disc)
                    .background(discColor, in: Circle())
                    .cardShadow()
                Text(text)
                    .font(isCompact ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, isCompact ? DS.Spacing.xs : DS.Spacing.m)
                    .padding(.vertical, isCompact ? 3 : 6)
                    .background(DS.Palette.card, in: Capsule())
            }
        }
    }

    private var wash: Color {
        switch kind {
        case .delete: DS.Palette.brick.opacity(0.25)
        case .keep: DS.Palette.ink.opacity(0.1)
        case .later: DS.Palette.card.opacity(0.3)
        }
    }

    private var discColor: Color {
        switch kind {
        case .delete: DS.Palette.brick
        case .keep: DS.Palette.ink
        case .later: DS.Palette.card
        }
    }

    private var icon: String {
        switch kind {
        case .delete: "trash"
        case .keep: "checkmark"
        case .later: "arrow.up"
        }
    }

    private var iconColor: Color { kind == .later ? DS.Palette.ink : .white }

    private var textColor: Color { kind == .delete ? DS.Palette.brick : DS.Palette.ink }
}

#Preview {
    HStack(spacing: 8) {
        SwipeStamp(kind: .delete, text: "Delete · 3.4 MB")
        SwipeStamp(kind: .keep, text: "Keep", isCompact: true)
    }
    .frame(height: 260)
    .padding()
    .background(DS.Palette.muted)
}
