import SwiftUI

struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @State var visitedStates: [String] = []

    var body: some View {
        VStack {
            MapView(visitedStates: $visitedStates, locationManager: locationManager)
                .edgesIgnoringSafeArea(.all)
            HStack {
                Button(action: {
                    locationManager.clearLocalData()
                }) {
                    Text("Clear Local Data")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                Button(action: {
                    locationManager.clearAllData()
                }) {
                    Text("Clear All Data")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
        }
        .onAppear {
            visitedStates = locationManager.visitedStates
        }
        .onChange(of: locationManager.visitedStates) { newValue in
            visitedStates = newValue
        }
    }
}
