import SwiftUI

/// Second onboarding screen: explains the one permission right before iOS asks for it, then
/// shows access granted and the first session underway before onboarding moves on.
struct PhotoAccessPrimerView: View {
    /// `preparing` is the moment after access is granted; `granted` is the primer seen again later,
    /// which shows the same steps but just continues.
    enum Progress { case idle, requesting, preparing, granted }

    let progress: Progress
    let onContinue: () -> Void

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
                .padding(.top, DS.Spacing.l)
                .onboardingEntrance(order: 0)
            Text("To find similar shots and blurry ones, \(AppInfo.name) needs to see your whole library.")
                .font(.body)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.m)
                .onboardingEntrance(order: 1)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    StepRow(
                        number: i + 1,
                        title: step.0,
                        detail: step.1,
                        status: status(ofStep: i),
                        isLast: i == steps.count - 1
                    )
                    .onboardingEntrance(order: 2 + i)
                }
            }
            .padding(.top, DS.Spacing.xxl)
            .animation(DS.Motion.calm, value: progress)
        }
        .onboardingLayout(footerOrder: 2 + steps.count) {
            VStack(spacing: DS.Spacing.m) {
                Button(action: onContinue) { buttonLabel }
                    .buttonStyle(.pill(.ink))
                    // Not `.disabled`, which would dim the button while it shows progress.
                    .allowsHitTesting(progress == .idle || progress == .granted)
                    .accessibilityLabel("Continue")
                    .accessibilityValue(progress == .preparing ? "Finding your first photos" : "")
                    .accessibilityIdentifier("onboarding.access.continue")
                Text("Limited access works too, you'll just see fewer suggestions.")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Both labels are always laid out, so the button keeps its size when it switches.
    private var buttonLabel: some View {
        let isPreparing = progress == .preparing
        return ZStack {
            Text("Continue")
                .opacity(isPreparing ? 0 : 1)
            HStack(spacing: DS.Spacing.xs) {
                ProgressView()
                    .tint(.white)
                Text("Finding your first photos…")
            }
            .opacity(isPreparing ? 1 : 0)
        }
        .multilineTextAlignment(.center)
        .animation(DS.Motion.calm, value: isPreparing)
    }

    private func status(ofStep i: Int) -> StepRow.Status {
        guard progress == .preparing || progress == .granted else { return .idle }
        return switch i {
        case 0: .done
        case 1: .active
        default: .waiting
        }
    }
}

private struct StepRow: View {
    /// Idle before access is granted; afterward step 1 is done and step 2 is underway.
    enum Status { case idle, done, active, waiting }

    let number: Int
    let title: String
    let detail: String
    let status: Status
    /// The last step has no rule running down to the next one.
    let isLast: Bool

    @ScaledMetric(relativeTo: .title2) private var markWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .title2) private var markHeight: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.l) {
            mark
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(status == .waiting ? DS.Palette.secondary : DS.Palette.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
            }
        }
        .padding(.bottom, isLast ? 0 : DS.Spacing.xl)
        .background(alignment: .topLeading) {
            if !isLast {
                // Connects this step's mark to the next one; grows with the row.
                Rectangle()
                    .fill(DS.Palette.line)
                    .frame(width: 1)
                    .padding(.top, markHeight + DS.Spacing.xxs)
                    .padding(.bottom, DS.Spacing.xxs)
                    .padding(.leading, markWidth / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The numeral always holds the space, so swapping in the checkmark never moves the row.
    private var mark: some View {
        let isDone = status == .done
        return Text("\(number)")
            .dsSerif(28, relativeTo: .title2)
            .foregroundStyle(markColor)
            .opacity(isDone ? 0 : 1)
            .blur(radius: isDone ? 4 : 0)
            .scaleEffect(isDone ? 0.6 : 1)
            .frame(width: markWidth)
            .overlay {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DS.Palette.brick)
                        .transition(.blurReplace)
                }
            }
    }

    private var markColor: Color {
        switch status {
        case .idle, .done: DS.Palette.brick
        case .active: DS.Palette.ink
        case .waiting: DS.Palette.secondary
        }
    }

    private var accessibilityText: String {
        let state = switch status {
        case .done: ", done"
        case .active: ", in progress"
        case .idle, .waiting: ""
        }
        return "Step \(number)\(state), \(title). \(detail)"
    }
}

#Preview("Idle") {
    PhotoAccessPrimerView(progress: .idle, onContinue: {})
        .background(DS.Palette.paper)
}

#Preview("Preparing") {
    PhotoAccessPrimerView(progress: .preparing, onContinue: {})
        .background(DS.Palette.paper)
}

#Preview("Granted, revisited") {
    PhotoAccessPrimerView(progress: .granted, onContinue: {})
        .background(DS.Palette.paper)
}
