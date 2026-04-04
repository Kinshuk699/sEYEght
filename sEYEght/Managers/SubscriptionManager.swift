//
//  SubscriptionManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import StoreKit

/// Manages AI Vision subscription via StoreKit 2 + daily free trial.
@Observable
final class SubscriptionManager {
    var isSubscribed = false
    var products: [Product] = []

    /// Number of free AI descriptions remaining today
    var freeUsesRemaining: Int = 3

    private let productIDs = ["com.seyeght.aivision.monthly", "com.seyeght.aivision.annual"]
    private let maxFreePerDay = 3
    private let freeUsesKey = "seyeght.freeAIUses"
    private let freeUsesDateKey = "seyeght.freeAIUsesDate"

    init() {
        loadFreeUses()
        print("[SubscriptionManager] Free uses remaining today: \(freeUsesRemaining)")
    }

    #if DEBUG
    /// Reset free uses for testing — call from console or debug menu
    func resetFreeUsesForTesting() {
        freeUsesRemaining = maxFreePerDay
        saveFreeUses()
        print("[SubscriptionManager] 🔧 DEBUG: Reset free uses to \(maxFreePerDay)")
    }
    #endif

    /// Whether the user can use AI Vision (subscribed OR has free uses left)
    var canUseAIVision: Bool {
        isSubscribed || freeUsesRemaining > 0
    }

    /// Consume one free use. Returns true if allowed, false if exhausted.
    func consumeFreeUse() -> Bool {
        guard !isSubscribed else { return true }  // Subscribers don't consume free uses
        loadFreeUses()  // Refresh in case day rolled over
        guard freeUsesRemaining > 0 else { return false }
        freeUsesRemaining -= 1
        saveFreeUses()
        print("[SubscriptionManager] Free use consumed. \(freeUsesRemaining) remaining today.")
        return true
    }

    private func loadFreeUses() {
        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())
        let savedDate = defaults.object(forKey: freeUsesDateKey) as? Date ?? .distantPast

        if Calendar.current.isDate(today, inSameDayAs: savedDate) {
            freeUsesRemaining = defaults.integer(forKey: freeUsesKey)
        } else {
            // New day — reset
            freeUsesRemaining = maxFreePerDay
            saveFreeUses()
        }
    }

    private func saveFreeUses() {
        let defaults = UserDefaults.standard
        defaults.set(freeUsesRemaining, forKey: freeUsesKey)
        defaults.set(Calendar.current.startOfDay(for: Date()), forKey: freeUsesDateKey)
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
            print("[SubscriptionManager] Loaded \(products.count) products")
        } catch {
            print("[SubscriptionManager] ❌ Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                isSubscribed = true
                await transaction.finish()
                print("[SubscriptionManager] ✅ Purchase successful: \(product.id)")
            case .userCancelled:
                print("[SubscriptionManager] User cancelled purchase")
            case .pending:
                print("[SubscriptionManager] Purchase pending")
            @unknown default:
                print("[SubscriptionManager] Unknown purchase result")
            }
        } catch {
            print("[SubscriptionManager] ❌ Purchase failed: \(error)")
        }
    }

    func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if productIDs.contains(transaction.productID) {
                    isSubscribed = true
                    print("[SubscriptionManager] ✅ Restored: \(transaction.productID)")
                }
            }
        }
    }

    func checkSubscriptionStatus() async {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if productIDs.contains(transaction.productID) {
                    isSubscribed = true
                    return
                }
            }
        }
        isSubscribed = false
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}
