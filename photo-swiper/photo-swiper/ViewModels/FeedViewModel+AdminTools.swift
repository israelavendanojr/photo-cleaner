import Foundation

// MARK: - Settings' Admin Tools

/// Settings' Admin Tools section, shown in Developer mode (see `DevMode`).
extension FeedViewModel {
    /// Replaces the free swipes left. Nil fills them to the cap.
    func debugSetSwipes(_ balance: Int?) {
        allowance = balance.map { SwipeAllowance(balance: $0, tunables: allowanceTunables, now: now()) }
            ?? SwipeAllowance(tunables: allowanceTunables, now: now())
        allowanceStore.save(allowance)
    }

    #if DEBUG
    /// Flips the stand-in purchase. Only the mock store can, and mocks are debug-only.
    func debugSetUnlocked(_ unlocked: Bool) {
        (entitlements as? DebugEntitlementStore)?.setUnlocked(unlocked)
        if unlocked { reminders.cancelAll() }
    }
    #endif

    /// The override over the real StoreKit store. Nil on mocks, which use `debugSetUnlocked`.
    var debugUnlockOverride: UnlockOverride? {
        (entitlements as? DebugOverrideEntitlementStore)?.override
    }

    /// What StoreKit itself says, under the override. Nil on mocks.
    var debugStoreKitUnlocked: Bool? {
        (entitlements as? DebugOverrideEntitlementStore)?.base.isUnlocked
    }

    func debugSetUnlockOverride(_ override: UnlockOverride) {
        (entitlements as? DebugOverrideEntitlementStore)?.setOverride(override)
        if isUnlocked { reminders.cancelAll() }
    }

    /// Onboarding and the swipe hint show again on the next launch.
    func debugResetOnboarding() {
        defaults.removeObject(forKey: DefaultsKey.hasOnboarded)
        defaults.removeObject(forKey: DefaultsKey.hasSeenSwipeHint)
        // Access is usually granted by now, which on its own skips onboarding.
        defaults.set(true, forKey: DefaultsKey.debugShowOnboarding)
    }

    /// Forgets every saved decision, the pile, and preferences, then deals a fresh first deck.
    func debugClearAllDecisions() async {
        store.reset()
        settledIDs = []
        skipFavorites = store.skipFavorites
        apply(await makeSession(number: 1))
        refreshTotals()
    }

    /// Progress reads 100% while on. Only what's shown changes; nothing is saved.
    func debugSetSimulatesComplete(_ on: Bool) {
        debugSimulatesComplete = on
        updateCelebration()
    }

    /// Plays the 100% confetti now.
    func debugPlayCelebration() {
        celebrationRequest += 1
    }

    /// Forgets that the 100% confetti played, so it plays again at 100%.
    func debugResetCelebration() {
        hasCelebratedComplete = false
        defaults.removeObject(forKey: DefaultsKey.celebratedComplete)
    }

    // MARK: Upsell

    /// The next delete offers the unlock again: forgets when it last showed and that the wall showed this session.
    func adminResetDeleteUpsell() {
        followUps.adminResetDeleteUpsell()
    }

    /// Asks RootView to show an upsell screen now, once Settings has closed.
    func adminRaiseUpsell(_ screen: AdminUpsell) {
        if screen == .postDelete {
            followUps.adminPickFreedBytes()
        }
        adminUpsellRequest = screen
    }

    /// RootView showed the requested upsell.
    func finishAdminUpsell() {
        adminUpsellRequest = nil
    }

    // MARK: Mock cards

    /// Puts an Admin Tools mock card on top of the deck, even from caught up.
    func adminInsertMockCard(_ card: FeedCard) {
        guard var current = session else { return }
        current.cards.insert(card, at: min(index, current.cards.count))
        session = current
        returningCard = nil
        if deckPhase == .caughtUp { enterDeckPhase(.feed) }
        saveProgress()
        adminShowFeedRequest += 1
    }

    /// Takes the mock cards still ahead out of the deck. Swiped ones stay behind until trimmed.
    func adminRemoveMockCards() {
        guard var current = session, current.cards[index...].contains(where: \.isAdminMock) else { return }
        current.cards = Array(current.cards[..<index]) + current.cards[index...].filter { !$0.isAdminMock }
        session = current
        returningCard = nil
        saveProgress()
        fillIfNeeded()
    }

    // MARK: Developer mode

    /// Settings' Developer mode switch. Turning it off also drops the unlock override and the
    /// simulated 100%, and the free tier goes back to its defaults.
    func setDevModeEnabled(_ enabled: Bool) {
        let before = allowanceTunables
        DevMode.shared.setEnabled(enabled)
        devModeChanged(from: before)
    }

    /// A tap on Settings' version row. Returns the toast to show when it flipped Developer mode.
    func registerVersionTap() -> String? {
        let before = allowanceTunables
        guard let toast = DevMode.shared.registerVersionTap() else { return nil }
        devModeChanged(from: before)
        return toast
    }

    /// Changes one free-tier limit; it applies right away.
    func setFreeTierValue(_ tunable: FreeTierTunable, _ value: Int) {
        let before = allowanceTunables
        freeTier.set(tunable, value)
        freeTierChanged(from: before)
    }

    func resetFreeTierToDefaults() {
        let before = allowanceTunables
        freeTier.resetToDefaults()
        freeTierChanged(from: before)
    }

    private func devModeChanged(from before: SwipeAllowance.Tunables) {
        if !DevMode.shared.isEnabled {
            (entitlements as? DebugOverrideEntitlementStore)?.setOverride(.off)
            if debugSimulatesComplete { debugSetSimulatesComplete(false) }
        }
        freeTierChanged(from: before)
    }

    /// Fits the saved allowance to new swipe tunables, and re-times a pending refill reminder.
    private func freeTierChanged(from before: SwipeAllowance.Tunables) {
        let after = allowanceTunables
        guard after != before else { return }
        allowance.adjust(from: before, to: after, at: now())
        allowanceStore.save(allowance)
        if !isUnlocked, allowance.remaining == 0, isRemindersOptedIn {
            reminders.cancelAll()
            Task { await scheduleReminders() }
        }
    }
}
