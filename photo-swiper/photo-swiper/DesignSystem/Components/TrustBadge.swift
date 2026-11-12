import SwiftUI

/// "Processed on device": a quiet note that the numbers around it never left the phone. Ink on `muted`,
/// so it reads as a fact, not a feature. Only where it's true, which is everywhere in this app.
struct TrustBadge: View {
    var text = "Processed on device"

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(DS.Palette.ink)
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xxs)
        .background(DS.Palette.muted, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TrustBadge()
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
}
