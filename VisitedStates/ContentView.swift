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
    @State private var showAlwaysAlert = false
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
            checkAlwaysAuthorization()
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
        .alert(isPresented: $showAlwaysAlert) {
            Alert(
                title: Text("Location Permission Required"),
                message: Text("For automatic tracking of states you've visited, please consider setting location permission to 'Always Allow' in the Settings app. You can also manually select states without enabling location."),
                primaryButton: .default(Text("Open Settings"), action: {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString),
                       UIApplication.shared.canOpenURL(settingsUrl) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }),
                secondaryButton: .cancel(Text("Cancel"))
            )
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
            // Get the current UIWindow
            guard let window = UIApplication.shared.windows.first else {
                self.isSharePreparing = false
                return
            }
            
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
    
    private func renderMapForSharing(shareText: String) {
        guard showShareSheet else { return }  // If sheet was dismissed, don't continue
        
        // Take a screenshot of the current UI
        if let window = UIApplication.shared.windows.first {
            UIGraphicsBeginImageContextWithOptions(window.frame.size, false, UIScreen.main.scale)
            window.drawHierarchy(in: window.frame, afterScreenUpdates: true)
            
            if let screenshot = UIGraphicsGetImageFromCurrentImageContext() {
                UIGraphicsEndImageContext()
                
                // Update share items with the actual screenshot
                shareItems = [screenshot, shareText]
                shareImageReady = true
            } else {
                UIGraphicsEndImageContext()
            }
        }
        
        // Done preparing
        isSharePreparing = false
    }
    
    private func checkAlwaysAuthorization() {
        // Instead of checking synchronously, use the publisher
        dependencies.locationService.authorizationStatus
            .filter { $0 == .authorizedWhenInUse }
            .first()
            .sink { _ in
                guard !self.hasShownAlwaysAlert else { return }
                
                // Delay a little if needed so that the splash screen is finished
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showAlwaysAlert = true
                    self.hasShownAlwaysAlert = true
                }
            }
            .store(in: &cancellables)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppDependencies.mock())
    }
}
