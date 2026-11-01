import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import photo_swiper

/// The StoreKit store against Products.storekit in a local test session.
/// Serialized: the StoreKit test environment is shared by the whole process.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct StoreKitEntitlementStoreTests {
    private let session: SKTestSession

    init() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Products.storekit")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    private func makeStore(defaults: UserDefaults = freshDefaults()) async -> StoreKitEntitlementStore {
        let store = StoreKitEntitlementStore(defaults: defaults)
        await store.ready()
        return store
    }

    /// For changes that arrive through `Transaction.updates`.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    // MARK: Purchase

    @Test func loadsThePrice() async {
        let store = await makeStore()

        #expect(store.displayPrice == "$9.99")
        #expect(!store.isUnlocked)
    }

    @Test func aPurchaseUnlocksAndIsRemembered() async {
        let defaults = freshDefaults()
        let store = await makeStore(defaults: defaults)

        #expect(await store.unlock() == .purchased)

        #expect(store.isUnlocked)
        #expect(defaults.bool(forKey: DefaultsKey.storeKitUnlocked), "Cached for the next launch")
    }

    @Test func aCancelStaysLocked() async throws {
        let store = await makeStore()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)

        #expect(await store.unlock() == .cancelled)

        #expect(!store.isUnlocked)
    }

    @Test func aFailedTransactionIsAFailure() async throws {
        let store = await makeStore()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)

        #expect(await store.unlock() == .failed)

        #expect(!store.isUnlocked)
    }

    @Test func askToBuyIsPendingThenUnlocksWhenApproved() async throws {
        session.askToBuyEnabled = true
        let store = await makeStore()

        #expect(await store.unlock() == .pending)
        #expect(!store.isUnlocked)

        let waiting = try #require(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
        try session.approveAskToBuyTransaction(identifier: waiting.identifier)

        #expect(await eventually { store.isUnlocked })
    }

    @Test func aRefundRelocks() async throws {
        let defaults = freshDefaults()
        let store = await makeStore(defaults: defaults)
        #expect(await store.unlock() == .purchased)

        let bought = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: bought.identifier)

        #expect(await eventually { !store.isUnlocked })
        #expect(!defaults.bool(forKey: DefaultsKey.storeKitUnlocked))
    }

    // MARK: Launch

    @Test func aStaleCacheIsCorrectedAtLaunch() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: DefaultsKey.storeKitUnlocked)

        let store = StoreKitEntitlementStore(defaults: defaults)
        #expect(store.isUnlocked, "Starts from the cache, no locked flash")
        await store.ready()

        #expect(!store.isUnlocked, "Nothing was bought")
    }

    @Test func anEarlierPurchaseUnlocksAtLaunch() async throws {
        _ = try await session.buyProduct(identifier: StoreProducts.unlock)

        let store = await makeStore()

        #expect(store.isUnlocked)
    }

    // MARK: Restore

    @Test func restoreFindsAnExistingPurchase() async throws {
        // Bought before a reinstall: nothing cached on this device.
        _ = try await session.buyProduct(identifier: StoreProducts.unlock)
        let store = StoreKitEntitlementStore(defaults: freshDefaults())

        #expect(await store.restore() == .restored)

        #expect(store.isUnlocked)
    }

    @Test func restoreWithNothingBoughtFindsNothing() async {
        let store = await makeStore()

        #expect(await store.restore() == .nothingToRestore)

        #expect(!store.isUnlocked)
    }

    @Test func aFailedSyncIsAFailure() async {
        struct Offline: Error {}
        let store = StoreKitEntitlementStore(defaults: freshDefaults(), sync: { throw Offline() })
        await store.ready()

        #expect(await store.restore() == .failed)
    }

    // MARK: Debug override

    @Test func aReleaseStyleStoreIgnoresTheOverrideKey() async {
        let defaults = freshDefaults()
        defaults.set(UnlockOverride.unlocked.rawValue, forKey: DefaultsKey.debugUnlockOverride)

        let store = await makeStore(defaults: defaults)

        #expect(!store.isUnlocked)
    }

    @Test func theOverrideIsOffByDefaultAndFollowsStoreKit() async {
        let defaults = freshDefaults()
        let store = DebugOverrideEntitlementStore(base: await makeStore(defaults: defaults), defaults: defaults)
        #expect(store.override == .off)
        #expect(!store.isUnlocked)

        #expect(await store.unlock() == .purchased)

        #expect(store.isUnlocked)
    }

    @Test func aForcedOverrideWinsAndOutlivesTheLaunch() async {
        let defaults = freshDefaults()
        let base = await makeStore(defaults: defaults)
        let store = DebugOverrideEntitlementStore(base: base, defaults: defaults)

        store.setOverride(.unlocked)
        #expect(store.isUnlocked)
        #expect(!base.isUnlocked, "StoreKit still says not purchased")

        let relaunched = DebugOverrideEntitlementStore(base: base, defaults: defaults)
        #expect(relaunched.override == .unlocked)
        #expect(relaunched.isUnlocked)

        #expect(await store.unlock() == .purchased)
        store.setOverride(.locked)
        #expect(!store.isUnlocked)
        #expect(base.isUnlocked)
    }
}
