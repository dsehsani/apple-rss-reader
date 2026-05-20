//
//  StoreKitService.swift
//  Payam
//
//  StoreKit 2 integration for premium subscriptions.
//  Manages product listing, purchase flow, and transaction verification.
//

import Foundation
import StoreKit

@Observable
final class StoreKitService {

    static let shared = StoreKitService()

    // MARK: - Product IDs

    static let premiumMonthlyID = "com.payam.premium.monthly"
    static let premiumYearlyID  = "com.payam.premium.yearly"
    static let foundingMonthlyID = "com.payam.founding.monthly"
    static let foundingYearlyID  = "com.payam.founding.yearly"

    private static let allProductIDs: Set<String> = [
        premiumMonthlyID, premiumYearlyID,
        foundingMonthlyID, foundingYearlyID,
    ]

    // MARK: - State

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoading = false

    var hasActivePremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    var currentTier: SubscriptionTier {
        if purchasedProductIDs.contains(Self.foundingMonthlyID) ||
           purchasedProductIDs.contains(Self.foundingYearlyID) {
            return .founding
        }
        if purchasedProductIDs.contains(Self.premiumMonthlyID) ||
           purchasedProductIDs.contains(Self.premiumYearlyID) {
            return .premium
        }
        return .free
    }

    // MARK: - Init

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: Self.allProductIDs)
                .sorted { $0.price < $1.price }
        } catch {
            print("StoreKit: failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - Check Entitlements

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await self?.updatePurchasedProducts()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
