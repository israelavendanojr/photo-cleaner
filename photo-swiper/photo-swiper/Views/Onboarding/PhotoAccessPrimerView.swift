import SwiftUI

/// Second onboarding screen: explains the one permission right before iOS asks for it.
struct PhotoAccessPrimerView: View {
    /// True while the system prompt is up.
    let isRequesting: Bool
    let onAllow: () -> Void

    private let steps = [
        ("Allow access", "iOS will ask you next."),
        ("Start swiping right away", "Your most recent photos come first."),
        ("We keep looking, quietly", "The scan carries on in the background. Large libraries take a few minutes."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("One permission, then you're in.")
                .dsSerif(40, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, DS.Spacing.xxl)
                .onboardingEntrance()
            Text("To find similar shots and blurry ones, \(AppInfo.name) needs to see your whole library.")
                .font(.body)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.m)
                .onboardingEntrance()
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    StepRow(number: i + 1, title: step.0, detail: step.1)
                        .onboardingEntrance(delay: 0.2 + Double(i) * 0.12)
                }
            }
            .padding(.top, DS.Spacing.xxl)
        }
        .onboardingLayout {
            VStack(spacing: DS.Spacing.m) {
                Button("Allow Photo Access", action: onAllow)
                    .buttonStyle(.pill(.ink))
                    .disabled(isRequesting)
                Text("Limited access works too, you'll just see fewer suggestions.")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.l) {
            Text("\(number)")
                .dsSerif(28, relativeTo: .title2)
                .foregroundStyle(DS.Palette.brick)
                .frame(minWidth: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number), \(title). \(detail)")
    }
}

#Preview {
    PhotoAccessPrimerView(isRequesting: false, onAllow: {})
}
