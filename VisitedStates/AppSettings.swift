import SwiftUI
import UIKit

/// A property wrapper to persist SwiftUI Colors using UserDefaults.
@propertyWrapper
struct UserDefaultColor {
    let key: String
    let defaultValue: Color

    var wrappedValue: Color {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
                return Color(uiColor)
            }
            return defaultValue
        }
        set {
            let uiColor = UIColor(newValue)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
    
    static func readColor(forKey key: String, defaultValue: Color) -> Color {
        if let data = UserDefaults.standard.data(forKey: key),
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
            return Color(uiColor)
        }
        return defaultValue
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // Private stored properties for reading/writing from UserDefaults
    @UserDefaultColor(key: "stateFillColor", defaultValue: .red)
    private var storedFillColor: Color
    
    @UserDefaultColor(key: "stateStrokeColor", defaultValue: .white)
    private var storedStrokeColor: Color
    
    @UserDefaultColor(key: "backgroundColor", defaultValue: .white)
    private var storedBackgroundColor: Color
    
    // Published backing properties for SwiftUI
    @Published private var fillColorBacking: Color
    @Published private var strokeColorBacking: Color
    @Published private var backgroundColorBacking: Color
    @AppStorage("visitedStatesString") private var storedVisitedStatesJSON: String = ""
    @Published private var visitedStatesBacking: [String] = []

    var visitedStates: [String] {
        get {
            visitedStatesBacking
        }
        set {
            visitedStatesBacking = newValue
            // Save to JSON
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                storedVisitedStatesJSON = json
            } else {
                storedVisitedStatesJSON = ""
            }
        }
    }

    // Example of other stored properties
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("speedThreshold") var speedThreshold: Double = 44.7
    @AppStorage("altitudeThreshold") var altitudeThreshold: Double = 3048
    @AppStorage("lastVisitedState") var lastVisitedState: String = ""
    @Published var hasPurchasedEditStates: Bool = IAPManager.shared.checkPurchased("neils.me.VisitedStates.editStates")
    
    // Computed property to determine if state editing is unlocked.
    var hasUnlockedStateEditing: Bool {
        return hasPurchasedEditStates
    }

    // Custom init to avoid "self used before init" errors
    private init() {
        fillColorBacking = UserDefaultColor.readColor(forKey: "stateFillColor", defaultValue: .red)
        strokeColorBacking = UserDefaultColor.readColor(forKey: "stateStrokeColor", defaultValue: .white)
        backgroundColorBacking = UserDefaultColor.readColor(forKey: "backgroundColor", defaultValue: .white)

        // Load from JSON on startup
        if let data = storedVisitedStatesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            visitedStatesBacking = decoded
        } else {
            visitedStatesBacking = []
        }
    }
    
    // Computed bridging properties: SwiftUI sees these changes.
    var stateFillColor: Color {
        get { fillColorBacking }
        set {
            fillColorBacking = newValue
            storedFillColor = newValue
        }
    }
    
    var stateStrokeColor: Color {
        get { strokeColorBacking }
        set {
            strokeColorBacking = newValue
            storedStrokeColor = newValue
        }
    }
    
    var backgroundColor: Color {
        get { backgroundColorBacking }
        set {
            backgroundColorBacking = newValue
            storedBackgroundColor = newValue
        }
    }
    
    func updatePurchasedProducts() {
        DispatchQueue.main.async {
            self.hasPurchasedEditStates = IAPManager.shared.checkPurchased("neils.me.VisitedStates.editStates")
        }
    }
    
    func restoreDefaults() {
        stateFillColor = .red
        stateStrokeColor = .white
        backgroundColor = .white
        
        notificationsEnabled = true
        speedThreshold = 44.7
        altitudeThreshold = 3048
        lastVisitedState = ""
    }
    
    @MainActor
    func purchaseStateEditing() async {
        // If no products have been fetched yet, try fetching them again.
        if IAPManager.shared.products.isEmpty {
            print("Products list empty, refetching products...")
            await IAPManager.shared.fetchProducts()
        }
        
        // Now log available product IDs for debugging.
        let availableProducts = IAPManager.shared.products.map { $0.id }
        print("Attempting to purchase state editing. Available products: \(availableProducts)")
        
        do {
            // Use the corrected product identifier with a lowercase "editStates".
            if let product = IAPManager.shared.products.first(where: { $0.id == "neils.me.VisitedStates.editStates" }) {
                try await IAPManager.shared.purchase(product)
                self.hasPurchasedEditStates = true
            } else {
                print("Product not found. Please check your product ID and configuration in App Store Connect.")
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }
}
