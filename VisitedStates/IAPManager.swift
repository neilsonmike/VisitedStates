import StoreKit

class IAPManager: NSObject, ObservableObject {
    
    static let shared = IAPManager()
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    
    private let productIDs = ["me.neils.VisitedStates.EditStates"]
    
    override private init() {
        super.init()
        Task {
            await fetchProducts()
            await checkPurchasedProducts()
        }
    }
    
    @MainActor
    func fetchProducts() async {
        do {
            self.products = try await Product.products(for: productIDs)
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        
        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            DispatchQueue.main.async {
                self.purchasedProductIDs.insert(product.id)
            }
            return true
        default:
            return false
        }
    }
    
    func checkPurchased(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }
    
    @MainActor
    func checkPurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchasedProductIDs.insert(transaction.productID)
            }
        }
    }
}//
//  IAPManager.swift
//  VisitedStates
//
//  Created by Mike Neilson on 3/14/25.
//

