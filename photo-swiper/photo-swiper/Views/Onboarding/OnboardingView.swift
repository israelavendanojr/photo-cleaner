import SwiftUI

/// First launch: Welcome, the photo access primer, then reminders and the unlock offer where they
/// apply. Nothing asks for access until the primer's Continue. Once access is granted the first deck
/// is dealt underneath while the last steps show.
///
/// Pages after Welcome have a back button and a progress bar. A sideways swipe anywhere goes back,
/// or forward to a page already reached, so a swipe never asks for anything or skips something unseen.
/// Going back past photo access shows it granted, so it never asks twice.
struct OnboardingView: View {
    enum Page: Hashable { case welcome, access, notifications, upsell }
    private enum Move: Equatable { case back, forward }
    /// A move waiting for the outgoing page to pick up its direction, numbered so repeats still register.
    private struct PendingMove: Equatable {
        let move: Move
        let id: Int
    }

    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Welcome or the primer, while the view model's step is `.intro`.
    @State private var introPage = Page.welcome
    /// The user has come back to the primer after access was granted, so it offers a plain Continue.
    @State private var hasRevisitedAccess = false
    /// The furthest page reached. Swiping forward goes no further than this.
    @State private var furthest = Page.welcome
    /// Which way the outgoing page drifts as it fades: `.leading` going forward, `.trailing` going back.
    @State private var direction = Edge.leading
    @State private var pendingMove: PendingMove?
    /// The finger's sideways travel in the swipe underway.
    @State private var dragX: CGFloat = 0
    /// Whether the drag underway is a sideways swipe. Decided on its first movement; nil between drags.
    @State private var isSwiping: Bool?
    @State private var hasCrossedCommit = false

    /// How long the primer shows access granted before moving on, so its checkmark can be read.
    private static let grantedPause = Duration.seconds(0.9)
    /// The back button and the space around it, which pages after Welcome start below.
    private static let topBarHeight: CGFloat = 44 + DS.Spacing.xs

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                pageView(current)
                    .id(current)
                    .offset(x: displacement(width: width))
                    .opacity(Double(1 - 0.25 * commitProgress(width: width)))
                    .environment(\.onboardingTopInset, current == .welcome ? 0 : Self.topBarHeight)
                    .transition(leaving(toward: direction))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Over the pages rather than above them, so Welcome keeps the room it doesn't need for it.
            .overlay(alignment: .top) { topBar(width: width) }
            .contentShape(Rectangle())
            .simultaneousGesture(swipe(width: width))
            .accessibilityAction(.escape) { request(.back) }
        }
        .background(DS.Palette.paper)
        // The steps after access change in the view model, often after an await, so they animate here.
        .animation(pageAnimation, value: vm.onboardingStep)
        .onChange(of: current, initial: true) { _, page in
            if index(of: page) > index(of: furthest) { furthest = page }
        }
        // Runs once the outgoing page has been drawn with the new direction, so it leaves that way.
        .onChange(of: pendingMove) { _, pending in
            guard let pending else { return }
            pendingMove = nil
            withAnimation(pageAnimation) {
                dragX = 0
                perform(pending.move)
            }
        }
        .task(id: vm.isOnboardingAccessGranted) {
            // Only full or limited access gets here; a denial goes straight to the no-access screen.
            guard vm.isOnboardingAccessGranted, vm.onboardingStep == .intro else { return }
            Haptics.accessGranted()
            try? await Task.sleep(for: Self.grantedPause)
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    // MARK: Pages

    /// Welcome, photo access, then the steps after it that apply.
    private var pages: [Page] {
        var pages: [Page] = [.welcome, .access]
        if vm.offersReminderStep { pages.append(.notifications) }
        if vm.offersUpsellStep { pages.append(.upsell) }
        return pages
    }

    private var current: Page {
        switch vm.onboardingStep {
        case .intro: introPage
        case .notifications: .notifications
        case .upsell: .upsell
        }
    }

    /// Where `page` falls in `pages`. A step that no longer applies, like the offer after a restore,
    /// counts as the last.
    private func index(of page: Page) -> Int {
        pages.firstIndex(of: page) ?? pages.count - 1
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        switch page {
        case .welcome:
            WelcomeView { request(.forward, bySwipe: false) }
        case .access:
            PhotoAccessPrimerView(progress: primerProgress) {
                Haptics.advance()
                if vm.isOnboardingAccessGranted {
                    advance()
                } else {
                    Task { await vm.start() }
                }
            }
        case .notifications:
            NotificationsPrimerView { advance() }
        case .upsell:
            UpsellView { advance() }
        }
    }

    /// The primer just after access is granted shows the first deck underway, then moves on.
    /// Seen again, it offers a plain Continue.
    private var primerProgress: PhotoAccessPrimerView.Progress {
        if vm.isOnboardingAccessGranted { return hasRevisitedAccess ? .granted : .preparing }
        return vm.isRequestingAccess ? .requesting : .idle
    }

    // MARK: Top bar

    private func topBar(width: CGFloat) -> some View {
        HStack(spacing: DS.Spacing.m) {
            CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { request(.back) }
                .opacity(canGoBack ? 1 : 0.4)
                .disabled(!canGoBack)
                .accessibilityIdentifier("onboarding.back")
            OnboardingProgressBar(fraction: progressFraction(width: width))
                // Follows the finger exactly; settles with a spring otherwise.
                .animation(isSwiping == true ? nil : DS.Motion.calm, value: progressFraction(width: width))
                .accessibilityLabel("Step \(index(of: current) + 1) of \(pages.count)")
                .accessibilityIdentifier("onboarding.progress")
            // The same width either way, so the bar never changes length.
            ZStack {
                if current == .upsell {
                    CircleIconButton(systemImage: "xmark", accessibilityLabel: "Continue for free", action: continueFree)
                        .disabled(vm.isPurchaseBusy || vm.isLeavingOnboarding)
                        .accessibilityIdentifier("onboarding.upsell.close")
                        .transition(.opacity)
                }
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.xs)
        // Welcome is the cover, without a bar; it fades in with the first step.
        .opacity(current == .welcome ? 0 : 1)
        .allowsHitTesting(current != .welcome)
        .accessibilityHidden(current == .welcome)
        .animation(pageAnimation, value: current)
        .animation(DS.Motion.calm, value: canGoBack)
    }

    /// How far through onboarding this is: Welcome is empty, the last step full, the steps between
    /// evenly spaced over the ones that apply. Mid-swipe, it leans toward the page the swipe heads for.
    private func progressFraction(width: CGFloat) -> Double {
        let last = max(pages.count - 1, 1)
        var position = Double(index(of: current))
        if allows(dragX), width > 0 {
            let lean = min(abs(dragX) / (width / 2), 1)
            position += dragX > 0 ? -lean : lean
        }
        return min(max(position / Double(last), 0), 1)
    }

    private func continueFree() {
        guard !vm.isPurchaseBusy else { return }
        Haptics.advance()
        advance()
    }

    // MARK: Moving between pages

    private var canGoBack: Bool {
        switch current {
        case .welcome: false
        // Not while the system prompt is up or the granted checkmark is showing.
        case .access: primerProgress == .idle || primerProgress == .granted
        case .notifications, .upsell: vm.canGoBackInOnboarding
        }
    }

    /// Forward by swiping, only to a page already reached, and never by doing what a button would ask.
    private var canGoForward: Bool {
        let next = index(of: current) + 1
        guard next < pages.count, next <= index(of: furthest) else { return false }
        switch current {
        case .welcome: return true
        // Access has to be granted from the button; swiping on past it doesn't ask again.
        case .access: return primerProgress == .granted
        // The same as "Not now".
        case .notifications: return vm.isOnboardingAccessGranted && !vm.isLeavingOnboarding
        case .upsell: return false
        }
    }

    private func allows(_ dx: CGFloat) -> Bool {
        dx > 0 ? canGoBack : dx < 0 ? canGoForward : false
    }

    /// On to the next step after photo access, or the feed, from a page's own button.
    private func advance() {
        direction = .leading
        Task { await vm.advanceOnboarding() }
    }

    /// Sets which way the current page will leave, then moves once that has been drawn. Welcome's
    /// own button goes forward to a page not yet reached; a swipe can't.
    private func request(_ move: Move, bySwipe: Bool = true) {
        let isAllowed = switch move {
        case .back: canGoBack
        case .forward: bySwipe ? canGoForward : current == .welcome
        }
        guard isAllowed else { return }
        // Welcome's button plays its own.
        if bySwipe { Haptics.advance() }
        direction = move == .back ? .trailing : .leading
        pendingMove = PendingMove(move: move, id: (pendingMove?.id ?? 0) + 1)
    }

    private func perform(_ move: Move) {
        switch (move, current) {
        case (.back, .access):
            introPage = .welcome
        case (.back, .notifications), (.back, .upsell):
            vm.goBackInOnboarding()
            if vm.onboardingStep == .intro {
                introPage = .access
                hasRevisitedAccess = true
            }
        case (.forward, .welcome):
            introPage = .access
        case (.forward, .access), (.forward, .notifications):
            Task { await vm.advanceOnboarding() }
        case (.back, .welcome), (.forward, .upsell):
            break
        }
    }

    // MARK: Swiping

    /// A sideways swipe anywhere moves a page; an upright one is left to scrolling. Let go past a fifth
    /// of the width, or flick, to go; otherwise the page settles back.
    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dx = value.translation.width
                if isSwiping == nil { isSwiping = abs(dx) > abs(value.translation.height) }
                guard isSwiping == true else { return }
                dragX = dx
                let crossed = allows(dx) && abs(dx) > commitDistance(width: width)
                if crossed != hasCrossedCommit {
                    hasCrossedCommit = crossed
                    if crossed { Haptics.threshold() }
                }
            }
            .onEnded { value in
                defer {
                    isSwiping = nil
                    hasCrossedCommit = false
                }
                guard isSwiping == true else { return }
                let dx = value.translation.width
                let flung = value.predictedEndTranslation.width
                let isFar = abs(dx) > commitDistance(width: width) || abs(flung) > width / 3
                // A flick back against the drag cancels it.
                if isFar, allows(dx), flung.sign == dx.sign {
                    request(dx > 0 ? .back : .forward)
                } else {
                    withAnimation(DS.Motion.page) { dragX = 0 }
                }
            }
    }

    private func commitDistance(width: CGFloat) -> CGFloat { width / 5 }

    /// 0 to 1 as an allowed swipe nears the point where letting go moves the page.
    private func commitProgress(width: CGFloat) -> CGFloat {
        guard allows(dragX), !reduceMotion, width > 0 else { return 0 }
        return min(abs(dragX) / commitDistance(width: width), 1)
    }

    /// The page follows the finger part of the way, easing off the further it goes, and barely moves
    /// toward a page it can't go to. Still with Reduce Motion.
    private func displacement(width: CGFloat) -> CGFloat {
        guard !reduceMotion, width > 0 else { return 0 }
        let reach = allows(dragX) ? width / 6 : width / 20
        return reach * tanh(dragX / (reach * 2.5))
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : DS.Motion.page
    }

    /// The incoming page appears at once and runs its own staggered entrance; the outgoing one
    /// fades as it drifts a little toward `edge`.
    private func leaving(toward edge: Edge) -> AnyTransition {
        let drift: CGFloat = reduceMotion ? 0 : 32
        return .asymmetric(
            insertion: reduceMotion ? .opacity : .identity,
            // Clears out quickly, so the headlines don't double up as the next page enters.
            removal: .opacity.combined(with: .offset(x: edge == .leading ? -drift : drift))
                .animation(.easeOut(duration: 0.22))
        )
    }
}

/// How far through onboarding the user is, as a bar that fills toward the last step.
private struct OnboardingProgressBar: View {
    /// 0 to 1.
    let fraction: Double

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(DS.Palette.line)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(DS.Palette.ink)
                        // Never narrower than it is tall, so the rounded ends keep their shape.
                        .frame(width: max(height, proxy.size.width * fraction))
                        .opacity(fraction > 0 ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

#if DEBUG
#Preview {
    let vm = FeedViewModel.mock(startingAt: .onboarding)
    OnboardingView()
        .environment(vm)
        // Puts the mock in onboarding, as launch does.
        .task { await vm.start() }
}

#Preview("Progress bar") {
    VStack(spacing: 20) {
        ForEach([0, 1.0 / 3, 2.0 / 3, 1], id: \.self) { OnboardingProgressBar(fraction: $0) }
    }
    .padding()
    .background(DS.Palette.paper)
}
#endif
