import SwiftUI
import MapKit

struct ContentView: View {
    @ObservedObject var locationManager = LocationManager()
    
    var body: some View {
        VStack {
            MapView(visitedStates: $locationManager.visitedStates, locationManager: locationManager)
                .edgesIgnoringSafeArea(.all)
        }
        .onAppear {
            locationManager.checkLocationAuthorization()
            locationManager.loadVisitedStates()
        }
    }
}
