import Foundation
import StoreKit
import Testing
@testable import photo_swiper

/// Which transactions unlock the app. `StoreKitEntitlementStoreTests` runs the same rule against a real
/// test session, but CI skips that suite, so the rule is pinned here on plain values.
struct UnlockRuleTests {
    @Test func onlyALiveTransactionOfOneOfOurProductsUnlocks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func plan(_ id: String, revoked: Date? = nil, expires: Date? = nil, upgraded: Bool = false) -> UnlockPlan.Kind? {
            StoreKitEntitlementStore.unlockingPlan(productID: id, revokedAt: revoked, expiresAt: expires, isUpgraded: upgraded, now: now)
        }
        #expect(plan(StoreProducts.unlock) == .once)
        #expect(plan(StoreProducts.monthly, expires: now.addingTimeInterval(60)) == .monthly)
        #expect(plan(StoreProducts.monthly, expires: now) == nil, "Over the moment it ends")
        #expect(plan(StoreProducts.monthly, expires: now.addingTimeInterval(-1)) == nil)
        #expect(plan(StoreProducts.monthly, revoked: now, expires: now.addingTimeInterval(60)) == nil, "Refunded")
        #expect(plan(StoreProducts.unlock, revoked: now) == nil)
        #expect(plan(StoreProducts.monthly, expires: now.addingTimeInterval(60), upgraded: true) == nil)
        #expect(plan("com.example.other") == nil)
    }

    @Test func eachPlanHasItsOwnProduct() {
        #expect(StoreProducts.id(for: .once) == "com.israelavendanojr.photo-swiper.unlock", "Permanent: purchases are tied to it")
        #expect(StoreProducts.id(for: .monthly) == "com.israelavendanojr.photo-swiper.monthly")
        for plan in UnlockPlan.Kind.allCases {
            #expect(StoreProducts.plan(for: StoreProducts.id(for: plan)) == plan)
        }
    }

    @Test func theLifetimeUnlockOutranksASubscription() {
        #expect(StoreKitEntitlementStore.activePlan(among: [.once, .monthly]) == .once)
        #expect(StoreKitEntitlementStore.activePlan(among: [.monthly]) == .monthly)
        #expect(StoreKitEntitlementStore.activePlan(among: [.once]) == .once)
        #expect(StoreKitEntitlementStore.activePlan(among: []) == nil)
    }

    @Test func aSubscriptionIsCheckedAgainJustAfterItEnds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let end = now.addingTimeInterval(3_600)
        #expect(StoreKitEntitlementStore.nextCheck(end: end, now: now) == end.addingTimeInterval(1))
    }

    /// Past its end but still entitled is a billing grace period, or a renewal that hasn't arrived:
    /// look again later, don't lock and don't spin.
    @Test func aSubscriptionPastItsEndIsCheckedAgainLater() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = now.addingTimeInterval(StoreKitEntitlementStore.recheckInterval)
        #expect(StoreKitEntitlementStore.nextCheck(end: now.addingTimeInterval(-60), now: now) == later)
        #expect(StoreKitEntitlementStore.nextCheck(end: now, now: now) == later)
    }

    /// The paywall says "per month" and nothing about a trial, so only that subscription is listed.
    @Test func onlyAPlainMonthlySubscriptionMatchesTheCopy() {
        func matches(_ period: Product.SubscriptionPeriod, offer: Bool = false) -> Bool {
            StoreKitEntitlementStore.matchesMonthlyCopy(period: period, hasIntroductoryOffer: offer)
        }
        #expect(matches(.monthly))
        #expect(!matches(.monthly, offer: true))
        #expect(!matches(.yearly))
        #expect(!matches(.weekly))
        #expect(!matches(.everyThreeMonths))
    }
}

struct DebugEntitlementStoreTests {
    @MainActor private func makeDefaults() -> UserDefaults {
        let name = "DebugEntitlementStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor @Test func aStandInPurchaseRemembersItsPlanAndRelockingForgetsIt() async {
        let store = DebugEntitlementStore(defaults: makeDefaults(), delay: .zero)
        #expect(store.activePlan == nil)

        #expect(await store.purchase(.monthly) == .purchased)
        #expect(store.isUnlocked)
        #expect(store.activePlan == .monthly)

        store.setUnlocked(false)
        #expect(!store.isUnlocked)
        #expect(store.activePlan == nil)
    }

    @MainActor @Test func theStandInStoreListsBothPlans() {
        let store = DebugEntitlementStore(defaults: makeDefaults(), delay: .zero)
        #expect(store.plans.map(\.kind) == [.once, .monthly])
    }
}
