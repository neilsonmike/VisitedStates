import StoreKit

class IAPManager: NSObject, ObservableObject {
    
    static let shared = IAPManager()
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    
    // Use the same product identifier as in AppSettings.
    private let productIDs = [Constants.editStatesProductID]
    
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
            print("Fetched products: \(products.map { $0.id })")
        } catch {
            print("Failed to fetch IAP products with error: \(error.localizedDescription)")
        }
    }
    
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        
        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            DispatchQueue.main.async {
                self.purchasedProductIDs.insert(product.id)
                // Persist the purchase flag so that future launches know the user bought it.
                UserDefaults.standard.set(true, forKey: "hasPurchasedEditStates")
            }
            return true
        default:
            print("Purchase failed or was cancelled for product ID: \(product.id)")
            return false
        }
    }
    
    func checkPurchased(_ productID: String) -> Bool {
        // Return true if either the persistent flag is set or the ephemeral set contains the product ID.
        return UserDefaults.standard.bool(forKey: "hasPurchasedEditStates") || purchasedProductIDs.contains(productID)
    }
    
    @MainActor
    func checkPurchasedProducts() async {
        purchasedProductIDs.removeAll()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchasedProductIDs.insert(transaction.productID)
            }
        }
        if !purchasedProductIDs.isEmpty {
            UserDefaults.standard.set(true, forKey: "hasPurchasedEditStates")
        }
        print("Purchased product IDs after restore: \(purchasedProductIDs)")
    }
    
    /// Refreshes purchased products by reloading current entitlements.
    @MainActor
    func restorePurchases() async {
        print("Restoring purchases...")
        await checkPurchasedProducts()
    }
}
