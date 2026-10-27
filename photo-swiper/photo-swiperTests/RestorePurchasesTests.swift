import Foundation
import Testing
@testable import photo_swiper

/// Restore from the wall or Settings, and the Settings reminders switch.
@MainActor
struct RestorePurchasesTests {
    private let entitlements = TestEntitlements(isUnlocked: false)

    private func vm(notifier: RefillNotifier? = nil) -> FeedViewModel {
        FeedViewModel.mock(entitlements: entitlements, notifier: notifier)
    }

    // MARK: Restore

    @Test func restoringFromSettingsUnlocksWithoutTheWall() async {
        let vm = vm()
        #expect(!vm.isWallPresented)

        #expect(await vm.restorePurchases())

        #expect(vm.paywallStatus == .restored)
        #expect(vm.isUnlocked)
        #expect(vm.purchasedThisLaunch)
    }

    @Test func restoringFromTheWallClosesIt() async {
        let vm = vm()
        vm.presentWall()

        #expect(await vm.restorePurchases())

        #expect(!vm.isWallPresented)
    }

    @Test func nothingFoundSaysSoAndStaysLocked() async {
        entitlements.restoreResult = .nothingToRestore
        let vm = vm()
        vm.presentWall()

        #expect(await vm.restorePurchases() == false)

        #expect(vm.paywallStatus == .nothingToRestore)
        #expect(!vm.isUnlocked)
        #expect(vm.isWallPresented, "The wall stays up to try again")
        #expect(!vm.purchasedThisLaunch)
    }

    @Test func anUnreachableStoreIsAFailureNotNothing() async {
        entitlements.restoreResult = .failed
        let vm = vm()

        #expect(await vm.restorePurchases() == false)

        #expect(vm.paywallStatus == .restoreFailed)
        #expect(!vm.isUnlocked)
    }

    @Test func restoringShowsProgressAndIgnoresASecondTap() async {
        let store = DebugEntitlementStore(defaults: freshDefaults(), delay: .milliseconds(300))
        let vm = FeedViewModel.mock(entitlements: store)

        let first = Task { await vm.restorePurchases() }
        for _ in 0..<50 where vm.paywallStatus != .restoring {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(vm.paywallStatus == .restoring)
        #expect(vm.isPurchaseBusy)
        #expect(await vm.restorePurchases() == false, "Ignored while one runs")
        vm.resetPurchaseStatus()
        #expect(vm.paywallStatus == .restoring, "Can't be cleared mid-restore")

        #expect(await first.value)
        #expect(vm.paywallStatus == .restored)
    }

    @Test func settingsClearsAnOldMessage() async {
        entitlements.restoreResult = .nothingToRestore
        let vm = vm()
        await vm.restorePurchases()

        vm.resetPurchaseStatus()

        #expect(vm.paywallStatus == .idle)
    }

    @Test func purchasingNoLongerNeedsTheWall() async {
        let vm = vm()

        #expect(await vm.purchaseUnlock())

        #expect(vm.isUnlocked)
        #expect(vm.paywallStatus == .idle)
    }

    // MARK: Reminders switch

    @Test func turningRemindersOnAsksAndOptsIn() async {
        let center = FakeNotificationCenter()
        let vm = vm(notifier: RefillNotifier(center: center, defaults: freshDefaults()))

        await vm.setRemindersEnabled(true)

        #expect(center.authorizationRequests == 1)
        #expect(vm.isRemindersOptedIn)
        #expect(!vm.areRemindersDenied)
    }

    @Test func turningRemindersOffCancelsWhatsScheduled() async {
        let center = FakeNotificationCenter()
        let defaults = freshDefaults()
        let notifier = RefillNotifier(center: center, defaults: defaults)
        let vm = vm(notifier: notifier)
        await vm.setRemindersEnabled(true)
        await notifier.scheduleOnEmpty(nextRefillAt: .now.addingTimeInterval(3600), fullAt: nil,
                                       tunables: .standard, estimate: nil, now: .now)
        #expect(!center.pending.isEmpty)

        await vm.setRemindersEnabled(false)

        #expect(center.pending.isEmpty)
        #expect(!vm.isRemindersOptedIn)
        #expect(!notifier.isOptedIn)
    }

    @Test func deniedInTheSettingsAppShowsOff() async {
        let center = FakeNotificationCenter()
        let vm = vm(notifier: RefillNotifier(center: center, defaults: freshDefaults()))
        await vm.setRemindersEnabled(true)

        center.denied = true
        await vm.refreshReminderPermission()

        #expect(vm.areRemindersDenied)
    }

    @Test func refusingPermissionMarksDenied() async {
        let center = FakeNotificationCenter()
        center.grants = false
        let vm = vm(notifier: RefillNotifier(center: center, defaults: freshDefaults()))

        await vm.setRemindersEnabled(true)

        #expect(!vm.isRemindersOptedIn)
        #expect(vm.areRemindersDenied)
    }
}
