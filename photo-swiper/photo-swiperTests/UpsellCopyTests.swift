import Foundation
import Testing
@testable import photo_swiper

/// The words on the unlock screens (JUN-44). They sit next to a price, so changes should be deliberate.
@MainActor
struct UpsellCopyTests {
    private let once = UnlockPlan(kind: .once, displayPrice: "$9.99")
    private let monthly = UnlockPlan(kind: .monthly, displayPrice: "$4.99")

    // MARK: What's included

    /// Each is true in code: free swipes are metered and the free pile is capped. Grouped cards are free
    /// too, so they aren't claimed.
    @Test func benefitsAreTheTwoThingsOnlyTheUnlockGives() {
        #expect(UnlockCopy.benefits.map(\.title) == ["Unlimited swipes", "No pile limit"])
        #expect(UnlockCopy.benefits.allSatisfy { !$0.systemImage.isEmpty && !$0.detail.isEmpty })
    }

    @Test func theUnlockReallyLiftsBothLimits() {
        let free = FeedViewModel.mock(entitlements: TestEntitlements(isUnlocked: false))
        let unlocked = FeedViewModel.mock(entitlements: TestEntitlements(isUnlocked: true))
        #expect(free.swipesLeft != nil)
        #expect(unlocked.swipesLeft == nil, "Unlimited swipes")
        #expect(free.pileLimitBytes != nil)
        #expect(unlocked.pileLimitBytes == nil, "No pile limit")
    }

    // MARK: Plans

    @Test func theButtonNamesThePlanAndItsPrice() {
        #expect(UnlockCopy.buttonTitle(for: once) == "Unlock for $9.99")
        #expect(UnlockCopy.buttonTitle(for: monthly) == "Subscribe for $4.99 / month")
        #expect(UnlockCopy.buttonAccessibilityLabel(for: once) == "Unlock for $9.99, one-time purchase")
        #expect(UnlockCopy.buttonAccessibilityLabel(for: monthly) == "Subscribe for $4.99 a month, renews monthly until cancelled")
    }

    @Test func theBillingNoteSaysHowTheChosenPlanIsBilled() {
        #expect(UnlockCopy.billingNote(for: once) == "One-time purchase. No renewals.")
        #expect(UnlockCopy.billingNote(for: monthly)
            == "\(AppInfo.name) Monthly: $4.99 per month, renewing automatically until you cancel in your Apple Account settings.")
    }

    @Test func eachPlanCardSaysHowItIsPaid() {
        #expect(UnlockCopy.title(for: .once) == "Once")
        #expect(UnlockCopy.detail(for: .once) == "Pay one time. Yours for good.")
        #expect(UnlockCopy.priceSuffix(for: .once) == nil)
        #expect(UnlockCopy.title(for: .monthly) == "Monthly")
        #expect(UnlockCopy.detail(for: .monthly) == "Renews each month. Cancel anytime.")
        #expect(UnlockCopy.priceSuffix(for: .monthly) == "/ month")
    }

    /// The price is the store's, wherever it's shown.
    @Test func noPriceIsWrittenIntoTheCopy() {
        let odd = UnlockPlan(kind: .monthly, displayPrice: "€3,49")
        #expect(UnlockCopy.buttonTitle(for: odd).contains("€3,49"))
        #expect(UnlockCopy.billingNote(for: odd).contains("€3,49"))
    }

    /// App Review (3.1.2) wants a subscription's name, length, price and how to cancel where it's sold.
    @Test func theSubscriptionTermsAreAllInTheBillingNote() {
        let note = UnlockCopy.billingNote(for: monthly)
        for part in [UnlockCopy.subscriptionName, "$4.99", "per month", "renewing automatically", "cancel"] {
            #expect(note.contains(part), "Missing: \(part)")
        }
        #expect(AppInfo.privacyPolicyURL != nil, "The paywall links the privacy policy beside the terms")
    }

    @Test func settingsSaysWhichPlanUnlocked() {
        #expect(UnlockCopy.unlockedTitle(subscribed: false).hasPrefix("Unlocked"))
        #expect(UnlockCopy.unlockedTitle(subscribed: true).hasPrefix("Subscribed monthly"))
        let entitlements = TestEntitlements(isUnlocked: true)
        entitlements.activePlan = .monthly
        #expect(FeedViewModel.mock(entitlements: entitlements).isSubscribed)
        entitlements.activePlan = .once
        #expect(!FeedViewModel.mock(entitlements: entitlements).isSubscribed, "The lifetime unlock has nothing to manage")
    }

    // MARK: Buying a plan

    @Test func thePaywallOffersWhatTheStoreLists() {
        let entitlements = TestEntitlements(isUnlocked: false)
        entitlements.plans = [UnlockPlan(kind: .once, displayPrice: "$9.99")]
        let vm = FeedViewModel.mock(entitlements: entitlements)
        #expect(vm.unlockPlans.map(\.kind) == [.once], "A plan the store doesn't list isn't offered")
    }

    @Test(arguments: UnlockPlan.Kind.allCases)
    func buyingAPlanAsksTheStoreForThatPlan(plan: UnlockPlan.Kind) async {
        let entitlements = TestEntitlements(isUnlocked: false)
        let vm = FeedViewModel.mock(entitlements: entitlements)
        #expect(await vm.purchaseUnlock(plan))
        #expect(entitlements.purchasedPlans == [plan])
        #expect(vm.isUnlocked, "Either plan unlocks")
    }

    // MARK: Status messages

    @Test(arguments: [PaywallStatus.idle, .purchasing, .restoring, .restored])
    func quietStatusesShowNoMessage(status: PaywallStatus) {
        #expect(UnlockCopy.message(for: status) == nil)
    }

    @Test func failuresAndWaitsExplainThemselves() {
        #expect(UnlockCopy.message(for: .purchaseFailed) == "The purchase didn't go through. If you were charged, use Restore.")
        #expect(UnlockCopy.message(for: .purchasePending) == "Waiting for approval. You'll be unlocked as soon as it's approved.")
        #expect(UnlockCopy.message(for: .nothingToRestore) == "We couldn't find an earlier purchase to restore.")
        #expect(UnlockCopy.message(for: .restoreFailed) == "Couldn't reach the App Store. Try again in a moment.")
    }

    /// Settings names a price only when the store has given one.
    @Test func settingsNamesThePriceOnlyOnceTheStoreHasIt() {
        #expect(UnlockCopy.settingsTitle(plans: [once, monthly]) == "Unlock for $9.99")
        #expect(UnlockCopy.settingsTitle(plans: [monthly]) == "Unlock \(AppInfo.name)")
        #expect(UnlockCopy.settingsTitle(plans: []) == "Unlock \(AppInfo.name)")
    }

    /// A subscriber may have cancelled already, so the row doesn't promise a renewal.
    @Test func theManageRowDoesNotPromiseARenewal() {
        #expect(UnlockCopy.manageSubscriptionDetail == "Change or cancel in your Apple Account.")
    }

    @MainActor @Test func openingAPaywallAsksTheStoreForMissingPlans() async {
        let entitlements = TestEntitlements(isUnlocked: false)
        let vm = FeedViewModel.mock(entitlements: entitlements)
        await vm.reloadUnlockPlans()
        #expect(entitlements.reloadCount == 1)
    }
}
