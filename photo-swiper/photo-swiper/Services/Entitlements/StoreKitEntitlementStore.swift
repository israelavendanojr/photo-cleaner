import Foundation
import Observation
import os
import StoreKit

/// What the App Store sells.
enum StoreProducts {
    /// The lifetime unlock, a non-consumable.
    static let unlock = "com.israelavendanojr.photo-swiper.unlock"
}

/// The unlock, bought and restored through StoreKit 2.
///
/// `isUnlocked` starts from the last known state so the app doesn't flash locked at launch, then
/// `Transaction.currentEntitlements` corrects it. Only verified, unrevoked transactions count.
/// `Transaction.updates` is watched for as long as the store lives (the life of the app), which
/// covers purchases on other devices, Ask to Buy approvals and refunds.
@Observable
@MainActor
final class StoreKitEntitlementStore: EntitlementStore {
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "entitlement")
    /// Shown until the product loads.
    static let fallbackPrice = "$9.99"

    private(set) var isUnlocked: Bool
    private var product: Product?
    var displayPrice: String { product?.displayPrice ?? Self.fallbackPrice }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sync: () async throws -> Void
    @ObservationIgnored nonisolated(unsafe) private var updates: Task<Void, Never>?
    @ObservationIgnored private var launch: Task<Void, Never>?

    /// `sync` is `AppStore.sync()`, replaceable in tests.
    init(defaults: UserDefaults = .standard, sync: @escaping () async throws -> Void = { try await AppStore.sync() }) {
        self.defaults = defaults
        self.sync = sync
        isUnlocked = defaults.bool(forKey: DefaultsKey.storeKitUnlocked)
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        launch = Task { [weak self] in
            await self?.finishUnfinished()
            await self?.loadProduct()
            await self?.refreshEntitlements()
        }
    }

    deinit {
        updates?.cancel()
    }

    /// Waits for the launch work: the product and the first entitlement check.
    func ready() async {
        await launch?.value
    }

    func unlock() async -> PurchaseOutcome {
        if product == nil { await loadProduct() }
        guard let product else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                setUnlocked(transaction.revocationDate == nil)
                return isUnlocked ? .purchased : .failed
            case .success(.unverified(_, let error)):
                Self.log.error("Purchase couldn't be verified: \(error.localizedDescription, privacy: .public)")
                return .failed
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            Self.log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    func restore() async -> RestoreOutcome {
        do {
            try await sync()
        } catch {
            Self.log.error("App Store sync failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
        await refreshEntitlements()
        return isUnlocked ? .restored : .nothingToRestore
    }

    /// Re-reads what this Apple Account owns.
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == StoreProducts.unlock,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
    }

    // MARK: Private

    private func handle(_ update: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = update {
            await transaction.finish()
        }
        await refreshEntitlements()
    }

    /// Anything verified but left unfinished, e.g. the app quit mid-purchase.
    private func finishUnfinished() async {
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
    }

    /// Tried at launch, and again on the next purchase if it failed.
    private func loadProduct() async {
        do {
            product = try await Product.products(for: [StoreProducts.unlock]).first
            if product == nil { Self.log.error("The unlock product wasn't found.") }
        } catch {
            Self.log.error("Couldn't load the unlock product: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setUnlocked(_ unlocked: Bool) {
        if isUnlocked != unlocked { isUnlocked = unlocked }
        defaults.set(unlocked, forKey: DefaultsKey.storeKitUnlocked)
    }
}
