import SwiftUI

@main
struct VisitedStatesApp: App {
    // Connect the AppDelegate to handle location-based app launch
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Create a single AppDependencies instance to manage all services
    @StateObject private var dependencies = AppDependencies.live()
    
    var body: some Scene {
        WindowGroup {
            IntroMapView()
                // Inject the dependencies through the environment
                .environmentObject(dependencies)
                .onAppear {
                    print("🟢 App is launching: VisitedStatesApp.swift")
                }
        }
    }
}
