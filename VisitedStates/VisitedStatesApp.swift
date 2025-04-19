import SwiftUI

@main
struct VisitedStatesApp: App {
    // Connect the AppDelegate to handle location-based app launch
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Create a single AppDependencies instance to manage all services
    @StateObject private var dependencies = AppDependencies.live()
    
    var body: some Scene {
        WindowGroup {
            // Show the IntroMapView directly
            IntroMapView()
                .environmentObject(dependencies)
                .onAppear {
                    print("🟢 App is launching: VisitedStatesApp.swift")
                    
                    // If app was launched by location services, start them
                    if appDelegate.launchedByLocationServices {
                        dependencies.locationService.startLocationUpdates()
                        dependencies.stateDetectionService.startStateDetection()
                        print("✅ Successfully restarted location services after device reboot")
                    }
                }
        }
    }
}
