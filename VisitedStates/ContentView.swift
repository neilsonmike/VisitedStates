import SwiftUI

struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @State private var visitedStates: [String] = []

    var body: some View {
        MapView(visitedStates: $visitedStates, locationManager: locationManager)
            .onAppear {
                visitedStates = locationManager.visitedStates
            }
    }
}
