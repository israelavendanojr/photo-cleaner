import SwiftUI

/// First onboarding screen: what the app does and what it never does with your photos.
struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StackedPhotosIllustration()
                .frame(maxWidth: .infinity)
            Text("Lighten your library.")
                .dsSerif(46, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, DS.Spacing.xl)
                .onboardingEntrance()
            Text("Clear the photos you don't need, one easy swipe at a time.")
                .font(.body)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.m)
                .onboardingEntrance()
            assurances
                .padding(.top, DS.Spacing.l)
                .onboardingEntrance()
        }
        .onboardingLayout {
            Button("Continue", action: onContinue)
                .buttonStyle(.pill(.ink))
                .accessibilityIdentifier("onboarding.welcome.continue")
        }
    }

    private var assurances: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            AssuranceRow(
                systemImage: "lock",
                title: "Everything stays on this iPhone.",
                detail: "Photos are sorted on-device. Nothing is uploaded, and there's no account to make."
            )
            AssuranceRow(
                systemImage: "arrow.uturn.backward",
                title: "Nothing is deleted until you confirm it.",
                detail: "Deleted photos stay in Recently Deleted for 30 days."
            )
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .softShadow()
    }
}

private struct AssuranceRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
