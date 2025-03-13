import SwiftUI

@main
struct VisitedStatesApp: App {
    @StateObject var settings = AppSettings.shared
    @StateObject var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            IntroMapView()
                .environmentObject(settings)
                .environmentObject(locationManager)
                .onAppear {
                    print("🟢 App is launching: VisitedStatesApp.swift")
                }
        }
    }
}
