import UIKit
import CoreLocation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Check if app was launched due to a location event
        if let _ = launchOptions?[UIApplication.LaunchOptionsKey.location] {
            print("🚀 App launched by location services after restart")
            
            // Start location services after a short delay to ensure app is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AppDependencies.live().locationService.startLocationUpdates()
                AppDependencies.live().stateDetectionService.startStateDetection()
            }
        }
        
        return true
    }
}
