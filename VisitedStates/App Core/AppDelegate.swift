import UIKit
import CoreLocation
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    // Flag to track if launched by location services
    var launchedByLocationServices = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Check if app was launched due to a location event
        if let _ = launchOptions?[UIApplication.LaunchOptionsKey.location] {
            print("🚀 App launched by location services after restart")
            launchedByLocationServices = true
        }

        // Testing CI API key integration
        print("📱 App launched with proper configuration")

        return true
    }

    // Other application delegate methods as needed
}
