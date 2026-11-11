import Foundation

/// Settings' Admin Tools section, shown in Developer mode (see `DevMode`). Views reach it as `vm.admin`.
///
/// It changes the deck only through `FeedViewModel`'s own intents, so nothing outside the view model
/// can set its state; it reaches the collaborators and the entitlement store directly, as the view
/// model would.
@MainActor
final class AdminController {
    private unowned let vm: FeedViewModel
    private let entitlements: any EntitlementStore
    private let defaults: UserDefaults

    init(vm: FeedViewModel, entitlements: any EntitlementStore, defaults: UserDefaults) {
        self.vm = vm
        self.entitlements = entitlements
        self.defaults = defaults
    }

    /// Replaces the free swipes left. Nil fills them to the cap.
    func debugSetSwipes(_ balance: Int?) {
        vm.gate.debugSetSwipes(balance)
    }

    #if DEBUG
    /// Flips the stand-in purchase. Only the mock store can, and mocks are debug-only.
    func debugSetUnlocked(_ unlocked: Bool) {
        (entitlements as? DebugEntitlementStore)?.setUnlocked(unlocked)
        if unlocked { vm.reminders.cancelAll() }
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
        if vm.isUnlocked { vm.reminders.cancelAll() }
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
        await vm.adminClearAllDecisions()
    }

    /// Progress reads 100% while on. Only what's shown changes; nothing is saved.
    func debugSetSimulatesComplete(_ on: Bool) {
        vm.adminSetSimulatesComplete(on)
    }

    /// Plays the 100% confetti now.
    func debugPlayCelebration() {
        vm.adminRequestCelebration()
    }

    /// Forgets that the 100% confetti played, so it plays again at 100%.
    func debugResetCelebration() {
        vm.adminResetCelebration()
    }

    // MARK: Upsell

    /// The next delete offers the unlock again: forgets when it last showed and that the wall showed this session.
    func adminResetDeleteUpsell() {
        vm.followUps.adminResetDeleteUpsell()
    }

    /// Readies an upsell screen the Admin tab is about to show over itself: a plausible headline for the
    /// post-delete offer, or the real wall (RootView presents it over any tab). The sheets and the
    /// onboarding pitch are presented by the Admin tab, so closing them lands back there.
    func adminRaiseUpsell(_ screen: AdminUpsell) {
        switch screen {
        case .postDelete: vm.followUps.adminPickFreedBytes()
        case .wall: vm.presentWall()
        case .onboarding, .unlockSheet: break
        }
    }

    // MARK: Mock cards

    /// Puts an Admin Tools mock card on top of the deck, even from caught up.
    func adminInsertMockCard(_ card: FeedCard) {
        vm.adminInsertMockCard(card)
    }

    /// Takes the mock cards still ahead out of the deck. Swiped ones stay behind until trimmed.
    func adminRemoveMockCards() {
        vm.adminRemoveMockCards()
    }

    // MARK: Developer mode

    /// Settings' Developer mode switch. Turning it off also drops the unlock override and the
    /// simulated 100%, and the free tier goes back to its defaults.
    func setDevModeEnabled(_ enabled: Bool) {
        let before = vm.allowanceTunables
        DevMode.shared.setEnabled(enabled)
        devModeChanged(from: before)
    }

    /// A tap on Settings' version row. Returns the toast to show when it flipped Developer mode.
    func registerVersionTap() -> String? {
        let before = vm.allowanceTunables
        guard let toast = DevMode.shared.registerVersionTap() else { return nil }
        devModeChanged(from: before)
        return toast
    }

    /// Changes one free-tier limit; it applies right away.
    func setFreeTierValue(_ tunable: FreeTierTunable, _ value: Int) {
        let before = vm.allowanceTunables
        vm.freeTier.set(tunable, value)
        freeTierChanged(from: before)
    }

    func resetFreeTierToDefaults() {
        let before = vm.allowanceTunables
        vm.freeTier.resetToDefaults()
        freeTierChanged(from: before)
    }

    // MARK: Feature availability

    /// Changes who gets one feature. The next page follows it; `adminRebuildDeck()` applies it now.
    func setFeatureAvailability(_ feature: TierFeature, _ availability: FeatureAvailability) {
        vm.features.set(feature, availability)
    }

    func resetFeatureAvailability() {
        vm.features.resetToDefaults()
    }

    /// Deals a fresh deck on the current rules, keeping every decision.
    func adminRebuildDeck() async {
        await vm.adminRebuildDeck()
    }

    private func devModeChanged(from before: SwipeAllowance.Tunables) {
        if !DevMode.shared.isEnabled {
            (entitlements as? DebugOverrideEntitlementStore)?.setOverride(.off)
            if vm.debugSimulatesComplete { debugSetSimulatesComplete(false) }
        }
        freeTierChanged(from: before)
    }

    /// Fits the saved allowance to new swipe tunables, and re-times a pending refill reminder.
    private func freeTierChanged(from before: SwipeAllowance.Tunables) {
        guard vm.gate.fitAllowance(from: before) else { return }
        if !vm.isUnlocked, vm.allowance.remaining == 0, vm.isRemindersOptedIn {
            vm.reminders.cancelAll()
            Task { await vm.scheduleReminders() }
        }
    }
}
