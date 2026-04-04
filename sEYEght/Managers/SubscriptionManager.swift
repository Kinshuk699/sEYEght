//
//  SubscriptionManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import StoreKit

/// Manages AI Vision subscription via StoreKit 2.
@Observable
final class SubscriptionManager {
    var isSubscribed = false
    var products: [Product] = []

    private let productIDs = ["com.seyeght.aivision.monthly", "com.seyeght.aivision.annual"]

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
