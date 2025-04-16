import SwiftUI
import UIKit
import CoreLocation

struct ContentView: View {
    @StateObject var locationManager = LocationManager.shared
    @StateObject var settings = AppSettings.shared
    @State private var showingSettings = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    
    // New state variable for always authorization alert
    @State private var showAlwaysAlert = false
    
    var body: some View {
        ZStack {
            // Display the MapView with environment object
            MapView()
                .environmentObject(settings)
                .environmentObject(locationManager)
                .edgesIgnoringSafeArea(.all)
            
            // Debug indicator for current simulated location
            GeometryReader { geometry in
                if let currentLocation = locationManager.currentLocation {
                    // Adjust coordinate transformation as needed.
                    let x = CGFloat(currentLocation.coordinate.longitude)
                    let y = CGFloat(currentLocation.coordinate.latitude)
                    
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .position(x: x, y: y)
                }
            }
            
            // Settings and share buttons
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Button(action: {
                            let renderer = ImageRenderer(content:
                                MapView()
                                    .environmentObject(settings)
                                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                            )
                            renderer.scale = UIScreen.main.scale

                            if let uiImage = renderer.uiImage {
                                // Calculate the state count, excluding "District of Columbia"
                                let stateCount = locationManager.visitedStates.filter { $0 != "District of Columbia" }.count
                                let stateText = stateCount == 1 ? "state" : "states"
                                // Append the App Store link
                                let shareText = "I have been to \(stateCount) \(stateText)! Track yours with the VisitedStates app! https://apps.apple.com/us/app/visitedstates/id6504059000"
                                shareItems = [uiImage, shareText]
                                showShareSheet = true
                            }
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        
                        Button(action: {
                            showingSettings.toggle()
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.title)
                                .padding(12)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.bottom, 16)
                    .padding(.trailing, 16)
                }
            }
        }
        .onAppear {
            checkAlwaysAuthorization()
        }

        // Present the settings sheet
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(locationManager)
        }
        // Present the share sheet
        .sheet(isPresented: Binding(
            get: { showShareSheet },
            set: { showShareSheet = $0 }
        )) {
            ShareSheet(activityItems: shareItems)
        }
        .alert(isPresented: $showAlwaysAlert) {
            Alert(title: Text("Location Permission Required"),
                  message: Text("Please change the location permission to 'Always Allow' in the Settings app."),
                  dismissButton: .default(Text("OK")))
        }
    }
    
    private func checkAlwaysAuthorization() {
        let status = CLLocationManager.authorizationStatus()
        if status == .authorizedWhenInUse {
            // Delay a little if needed so that the splash screen is finished
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showAlwaysAlert = true
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
