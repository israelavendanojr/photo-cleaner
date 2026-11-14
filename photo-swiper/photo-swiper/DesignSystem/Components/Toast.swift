import SwiftUI

/// A short note in an ink capsule, with an optional action, e.g. "Trim queued · saves ~335 MB · Undo".
/// It announces itself to VoiceOver when it appears. The caller decides how long it stays.
struct Toast: View {
    let text: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Text(text)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .underline()
                    .frame(minHeight: DS.Tap.minimum)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .frame(minHeight: DS.Tap.minimum)
        .background {
            Capsule()
                .fill(DS.Palette.ink)
                .softShadow()
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

#Preview {
    VStack(spacing: DS.Spacing.m) {
        Toast(text: "Trim queued · saves ~335 MB", actionTitle: "Undo")
        Toast(text: "Developer mode on")
        Toast(text: "Trim queued · saves ~335 MB", actionTitle: "Undo")
            .dynamicTypeSize(.xxLarge)
    }
    .padding()
    .background(DS.Palette.paper)
}
