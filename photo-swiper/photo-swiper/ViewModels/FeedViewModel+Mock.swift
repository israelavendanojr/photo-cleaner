import Foundation

// MARK: - Mock setup

#if DEBUG
extension FeedViewModel {
    /// Named starting points for previews and `-startAt` launch arguments.
    enum MockStart: String {
        case first, video, similar, batch, duplicates, onboarding
        /// Partway through the first page with a few deletes pending.
        case pending
        /// Locked with no swipes left, the wall up over the deck.
        case outOfSwipes
        case caughtUp
    }

    /// Mocks start locked unless `entitlements` says otherwise (or `-unlocked YES` in debug builds),
    /// with a full allowance unless `allowance` says otherwise.
    static func mock(
        startingAt start: MockStart = .first,
        entitlements: (any EntitlementStore)? = nil,
        allowance: SwipeAllowance? = nil,
        allowanceTunables: SwipeAllowance.Tunables = .standard,
        freeTier: FreeTierTunables? = nil,
        notifier: RefillNotifier? = nil
    ) -> FeedViewModel {
        let entitlements = entitlements ?? EntitlementServices.make(mock: true)
        if start == .onboarding {
            // Unstarted, on a library that hasn't been asked yet, with nothing remembered.
            // Previews get a stand-in notification center that hasn't asked, so the reminders step shows.
            let suite = "mock.onboarding"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            return FeedViewModel(
                library: MockPhotoLibrary(needsPrompt: true),
                builder: MockFeedBuilder(),
                entitlements: entitlements,
                defaults: defaults,
                firstSessionMinimum: onboardingPreparingMinimum,
                allowanceTunables: allowanceTunables,
                freeTier: freeTier,
                notifier: notifier ?? RefillNotifier(center: PreviewNotificationCenter(), defaults: defaults)
            )
        }
        let builder = MockFeedBuilder()
        let library = MockPhotoLibrary()
        let vm = FeedViewModel(
            library: library,
            builder: builder,
            entitlements: entitlements,
            session: builder.makeSessionNow(number: 1),
            stats: LibraryStats(totalItems: library.totalItems, reviewedItems: library.reviewedItems, freedBytes: 0),
            allowanceStore: SwipeAllowanceStore(initial: allowance),
            allowanceTunables: allowanceTunables,
            freeTier: freeTier,
            notifier: notifier
        )
        switch start {
        case .first:
            break
        case .video:
            vm.index = vm.cards.firstIndex { if case .video = $0 { true } else { false } } ?? 0
        case .similar:
            vm.index = vm.cards.firstIndex { if case .similar = $0 { true } else { false } } ?? 0
        case .batch:
            vm.index = vm.cards.firstIndex { if case .batch = $0 { true } else { false } } ?? 0
        case .duplicates:
            vm.index = vm.cards.firstIndex { if case .duplicates = $0 { true } else { false } } ?? 0
        case .pending:
            vm.simulateSwipes(10)
        case .outOfSwipes:
            vm.index = 4
            vm.gate.allowance = SwipeAllowance(balance: 0, tunables: allowanceTunables, now: .now)
            vm.presentWall()
        case .caughtUp:
            vm.apply(Session(number: 2, cards: []))
        case .onboarding:
            break
        }
        return vm
    }
}
#endif

#if DEBUG
extension FeedViewModel {

    /// Shows a wall state without going through a purchase, for previews.
    func previewWall(status: PaywallStatus) {
        gate.isWallPresented = true
        gate.paywallStatus = status
    }

    /// Decides the next `count` cards with a plausible mix of deletes, keeps, and laters.
    private func simulateSwipes(_ count: Int) {
        gate.chargesSwipes = false
        defer { gate.chargesSwipes = true }
        for _ in 0..<count where phase == .feed && currentCard != nil {
            let isVideo = if case .video = currentCard { true } else { false }
            let direction: SwipeDirection = switch index % 9 {
            case _ where isVideo: .right
            case 2, 6: .right
            case 4 where index < 20: .up
            default: .left
            }
            decide(direction)
        }
        dismissChip()
    }
}
#endif
