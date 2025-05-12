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
    @State private var showEditStates = false
    @State private var shareItems: [Any] = []
    @AppStorage("hasShownAlwaysAlert") private var hasShownAlwaysAlert = false
    // Removed automatic location prompt - using onboarding instead
    @State private var showLocationPermissionAlert = false // Kept for backward compatibility
    @State private var cancellables = Set<AnyCancellable>()
    @State private var visitedStates: [String] = []
    
    // Track if we need to show badges on settings button
    @State private var needsLocationUpgrade = false
    @State private var needsOptimalSettings = false // For Background App Refresh and Precise Location
    
    // New state variables for speed and altitude
    @State private var currentSpeed: Double = 0.0
    @State private var currentAltitude: Double = 0.0
    @State private var speedThreshold: Double = 100.0 // Default, will be updated from settings
    @State private var altitudeThreshold: Double = 10000.0 // Default, will be updated from settings
    
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
            
//            // Add speed and altitude indicators
//            VStack {
//                HStack {
//                    Spacer()
//                    VStack(alignment: .trailing, spacing: 4) {
//                        // Speed indicator
//                        Text("Detected Speed: \(Int(currentSpeed)) mph")
//                            .font(.system(size: 10))
//                            .foregroundColor(currentSpeed > speedThreshold ? .red : .gray)
//                        
//                        // Altitude indicator
//                        Text("Detected Altitude: \(Int(currentAltitude)) ft")
//                            .font(.system(size: 10))
//                            .foregroundColor(currentAltitude > altitudeThreshold ? .red : .gray)
//                    }
//                    .padding(8)
//                    .background(Color.black.opacity(0.2))
//                    .cornerRadius(8)
//                    .padding(.top, 40)
//                    .padding(.trailing, 16)
//                }
//                Spacer()
//            }
            
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
                                .font(.system(size: 20))
                                .frame(width: 40, height: 40)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        .disabled(isSharePreparing)
                        
                        // Edit States Button
                        Button(action: {
                            showEditStates.toggle()
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 20))
                                .frame(width: 40, height: 40)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        
                        // Settings Button with badge indicator for permissions
                        Button(action: {
                            showingSettings.toggle()
                        }) {
                            ZStack {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 20))
                                    .frame(width: 40, height: 40)
                                    .background(Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                                
                                // Show upgrade badge if needed
                                if needsLocationUpgrade {
                                    // Red location badge for main permission issue
                                    ZStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 18, height: 18)

                                        Image(systemName: "location.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white)
                                    }
                                    .offset(x: 14, y: -14)
                                } else if needsOptimalSettings {
                                    // Orange compass badge for secondary settings issues
                                    ZStack {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 18, height: 18)

                                        Image(systemName: "location.north.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white)
                                    }
                                    .offset(x: 14, y: -14)
                                }
                            }
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
        // Present the edit states sheet
        .sheet(isPresented: $showEditStates) {
            EditStatesView()
                .environmentObject(dependencies)
        }
        // Removed automatic 'Always' location permission alert - using onboarding instead
    }
    
    private func setupSubscriptions() {
        // Subscribe to visited states changes
        dependencies.settingsService.visitedStates
            .sink { states in
                self.visitedStates = states
            }
            .store(in: &cancellables)
    
        // Subscribe to RAW location updates to update speed and altitude
        // This ensures we get ALL updates, even those that are filtered out
        dependencies.locationService.rawLocationUpdates
            .sink { location in
                if let location = location {
                    // Convert m/s to mph for display, ensuring non-negative values
                    let speedMps = max(0, location.speed) // Ensure non-negative value
                    self.currentSpeed = speedMps * 2.23694
                    
                    // Convert meters to feet for display
                    self.currentAltitude = location.altitude * 3.28084
                    
                    // Debug log
                    print("📊 UI Updated - Speed: \(Int(self.currentSpeed)) mph, Altitude: \(Int(self.currentAltitude)) ft")
                }
            }
            .store(in: &cancellables)
            
        // Subscribe to threshold values from settings
        dependencies.settingsService.speedThreshold
            .sink { threshold in
                self.speedThreshold = threshold
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.altitudeThreshold
            .sink { threshold in
                self.altitudeThreshold = threshold
            }
            .store(in: &cancellables)
            
        // Subscribe to location authorization status changes
        dependencies.locationService.authorizationStatus
            .sink { status in
                // Update the badge state based on authorization status
                // Show badge for any permission state that isn't "Always"
                // This includes "While Using App", "Never", and "Not Determined"
                if status != .authorizedAlways {
                    self.needsLocationUpgrade = true
                    self.needsOptimalSettings = false // Hide the other badge if location is not "Always"
                } else {
                    self.needsLocationUpgrade = false
                    // If we have "Always" permission, check other settings
                    self.checkOptimalSettings()
                }
            }
            .store(in: &cancellables)

        // Subscribe to scene phase changes to refresh settings status
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { _ in
                // When app becomes active, recheck settings
                if self.dependencies.locationService.authorizationStatus.value == .authorizedAlways {
                    self.checkOptimalSettings()
                }
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
        
        // Use a smaller, more reasonable size for sharing (1200x1600)
        let shareWidth: CGFloat = 1200
        let shareHeight: CGFloat = 1600
        
        // Render the SharePreviewView for a better sharing experience
        DispatchQueue.main.async {
            // Create renderer for SharePreviewView
            let renderer = ImageRenderer(content:
                SharePreviewView()
                    .environmentObject(self.dependencies)
                    .frame(width: shareWidth, height: shareHeight)
                    .background(Color.white) // Ensure we have a solid background
            )
            
            // Set scale for proper resolution
            renderer.scale = UIScreen.main.scale
            
            // Instead of setting uiImageRendererFormat, we'll convert the image after rendering
            if var uiImage = renderer.uiImage {
                // Convert to a fully opaque image without alpha channel
                if let cgImage = uiImage.cgImage {
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                    
                    if let context = CGContext(data: nil,
                                              width: cgImage.width,
                                              height: cgImage.height,
                                              bitsPerComponent: 8,
                                              bytesPerRow: 0,
                                              space: colorSpace,
                                              bitmapInfo: bitmapInfo.rawValue) {
                        
                        let rect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
                        context.draw(cgImage, in: rect)
                        
                        if let newCGImage = context.makeImage() {
                            uiImage = UIImage(cgImage: newCGImage)
                        }
                    }
                }
                
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
        // The automatic 'Always' location permission alert has been removed
        // We're now using the Settings view to promote permission upgrades in a less intrusive way

        // Mark as shown to prevent any future attempts with the old system
        hasShownAlwaysAlert = true
        showLocationPermissionAlert = false

        // Check if we should show a badge on the Settings button to encourage upgrade
        let locationStatus = dependencies.locationService.authorizationStatus.value
        if locationStatus != .authorizedAlways {
            // Any permission state other than "Always" should show the badge
            // This includes "While Using App", "Never", and "Not Determined"
            needsLocationUpgrade = true
        } else {
            // Only "Always" permission is optimal, so no badge needed
            needsLocationUpgrade = false

            // If we have "Always" permission, check other optimal settings
            checkOptimalSettings()
        }
    }

    private func checkOptimalSettings() {
        // Check Background App Refresh status
        let backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        let isBackgroundRefreshEnabled = (backgroundRefreshStatus == .available)

        // Check Precise Location status
        let locationManager = CLLocationManager()
        let isPreciseLocationEnabled = locationManager.accuracyAuthorization == .fullAccuracy

        // Update indicator state - show if either setting is not optimal
        needsOptimalSettings = !isBackgroundRefreshEnabled || !isPreciseLocationEnabled

        print("🔍 Optimal settings check - Background Refresh: \(isBackgroundRefreshEnabled), Precise Location: \(isPreciseLocationEnabled)")
    }
}
