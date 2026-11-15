import Foundation
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
}
