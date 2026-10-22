import SwiftUI

/// Where the user lands after choosing to stop: what they've freed, how far through the library
/// they are, and anything still waiting to be deleted. Unlike caught-up, more is waiting.
struct RestView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.freedFigureNamespace) private var freedFigure
    var onOpenPile: () -> Void = {}
    var onSeeLibrary: () -> Void = {}

    private var pendingCount: Int { vm.pendingItems.count }
    /// Arriving straight from the celebration, the freed figure moves over instead of entering.
    private var carriesFigure: Bool { vm.celebration != nil && freedFigure != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Circle()
                .strokeBorder(DS.Palette.brick, lineWidth: 2)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
                .onboardingEntrance(order: 0)
            Text(vm.isWelcomeBack ? "Welcome back." : "That's enough for today.")
                .dsSerif(36, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, DS.Spacing.l)
                .onboardingEntrance(order: 1)
            Text(vm.isWelcomeBack ? "Pick up whenever you're ready." : "The rest of your library will wait.")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.xs)
                .onboardingEntrance(order: 2)
            if vm.freedBytes > 0, carriesFigure {
                freed
                    .padding(.top, DS.Spacing.xl)
            } else if vm.freedBytes > 0 {
                freed
                    .padding(.top, DS.Spacing.xl)
                    .onboardingEntrance(order: 3)
            }
            libraryProgress
                .padding(.top, DS.Spacing.xl)
                .onboardingEntrance(order: 4)
            if pendingCount > 0 {
                pendingRow
                    .padding(.top, DS.Spacing.l)
                    .onboardingEntrance(order: 5)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.calm, value: pendingCount)
        .onboardingLayout(footerOrder: 6) {
            VStack(spacing: DS.Spacing.s) {
                Button("Start another session") {
                    Task { await vm.requestNextSession() }
                }
                .buttonStyle(.pill(.ink))
                Button("See your library", action: onSeeLibrary)
                    .buttonStyle(.pill(.ghost))
            }
        }
        .background(DS.Palette.paper)
    }

    private var freed: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(Format.size(vm.freedBytes))
                .dsSerif(64, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.brick)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .freedFigure(in: carriesFigure ? freedFigure : nil)
            Text("freed so far")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var libraryProgress: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack {
                Text("Library reviewed")
                Spacer()
                Text("\(Int((vm.libraryReviewedFraction * 100).rounded()))%")
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Palette.ink)
            }
            .font(.subheadline)
            .foregroundStyle(DS.Palette.secondary)
            ProgressLine(value: vm.libraryReviewedFraction, tint: DS.Palette.brick, height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    /// Deleting from the pile always works, whatever else is locked.
    private var pendingRow: some View {
        Button(action: onOpenPile) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Palette.brick)
                    .frame(width: 36, height: 36)
                    .background(DS.Palette.brickTint, in: Circle())
                    .accessibilityHidden(true)
                Text("\(pendingCount) \(pendingCount == 1 ? "photo" : "photos") still marked to delete")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: DS.Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.secondary)
                    .accessibilityHidden(true)
            }
            .padding(DS.Spacing.s)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .strokeBorder(DS.Palette.line, lineWidth: 1)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityHint("Opens the photos waiting to be deleted")
        .accessibilityIdentifier("rest.pending")
    }
}

#Preview("Resting") {
    RestView()
        .environment(FeedViewModel.mock(startingAt: .celebratedRest))
}

#Preview("With pending") {
    RestView()
        .environment(FeedViewModel.mock(startingAt: .resting))
}

#Preview("Welcome back") {
    RestView()
        .environment(FeedViewModel.mock(startingAt: .welcomeBack))
}
