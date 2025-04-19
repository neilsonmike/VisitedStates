import SwiftUI
import UIKit
import CoreLocation
import Combine

struct ContentView: View {
    // Access app dependencies
    @EnvironmentObject var dependencies: AppDependencies
    
    // Local state
    @State private var showingSettings = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @AppStorage("hasShownAlwaysAlert") private var hasShownAlwaysAlert = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var visitedStates: [String] = []
    
    // For sharing
    @State private var isSharePreparing = false
    @State private var shareImageReady = false
    
    var body: some View {
        ZStack {
            // Display the MapView with dependencies
            MapView()
                .environmentObject(dependencies)
                .edgesIgnoringSafeArea(.all)
            
            // Debug indicator for current simulated location
            GeometryReader { geometry in
                if let currentLocation = dependencies.locationService.currentLocation.value {
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
                        // Share Button
                        Button(action: {
                            prepareShareContent()
                        }) {
                            Image(systemName: isSharePreparing ? "hourglass" : "square.and.arrow.up")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        .disabled(isSharePreparing)
                        
                        // Settings Button
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
            checkLocationPermission()
            setupSubscriptions()
            // Start location tracking and state detection
            dependencies.stateDetectionService.startStateDetection()
        }
        .onDisappear {
            cancellables.removeAll()
        }
        // Present the settings sheet
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(dependencies)
        }
        // Present the share sheet
        .sheet(isPresented: $showShareSheet, onDismiss: {
            isSharePreparing = false
            shareImageReady = false
        }) {
            ShareSheet(activityItems: shareItems)
        }
    }
    
    private func setupSubscriptions() {
        // Subscribe to visited states changes
        dependencies.settingsService.visitedStates
            .sink { states in
                self.visitedStates = states
            }
            .store(in: &cancellables)
    
        // Subscribe to current location updates if needed
        dependencies.locationService.currentLocation
            .sink { location in
                // Handle location updates if needed
            }
            .store(in: &cancellables)
        
        // Subscribe to state detection - BUT DON'T TRIGGER NOTIFICATIONS HERE
        // Just observe the state changes for UI updates
        dependencies.stateDetectionService.currentDetectedState
            .compactMap { $0 }
            .sink { state in
                // No longer calling handleDetectedState here
                // Just observe the state change for UI purposes
                print("👁️ ContentView observed state change to: \(state)")
            }
            .store(in: &cancellables)
    }
    
    private func prepareShareContent() {
        // Start preparing
        isSharePreparing = true
        
        // Render the map view first, then show the share sheet when ready
        DispatchQueue.main.async {
            // Create renderer for MapView
            let renderer = ImageRenderer(content:
                MapView()
                    .environmentObject(self.dependencies)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
            )
            
            // Set scale to screen scale for proper resolution
            renderer.scale = UIScreen.main.scale
            
            if let uiImage = renderer.uiImage {
                // Create share text
                let stateCount = self.visitedStates
                    .filter { $0 != "District of Columbia" }
                    .count
                let stateText = stateCount == 1 ? "state" : "states"
                let shareText = "I have been to \(stateCount) \(stateText)! Track yours with the VisitedStates app! https://apps.apple.com/us/app/visitedstates/id6504059000"
                
                // Set share items
                self.shareItems = [uiImage, shareText]
                
                // Now show the share sheet with the prepared content
                self.isSharePreparing = false
                self.showShareSheet = true
            } else {
                // Fallback if image rendering fails
                print("Failed to render map image")
                self.isSharePreparing = false
            }
        }
    }
    
    private func checkLocationPermission() {
        let status = dependencies.locationService.authorizationStatus.value
        if status == .denied || status == .restricted {
            // You could show an alert explaining that location is needed
            // for state detection but not required for manual selection
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppDependencies.mock())
    }
}
