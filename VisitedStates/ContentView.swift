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
    @State private var showLocationPermissionAlert = false
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
                        
                        // Edit States Button
                        Button(action: {
                            showEditStates.toggle()
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        
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
        // Present the edit states sheet
        .sheet(isPresented: $showEditStates) {
            EditStatesView()
                .environmentObject(dependencies)
        }
        // Show location permission alert
        .alert("Enable 'Always' Location Access", isPresented: $showLocationPermissionAlert) {
            Button("Open Settings", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Later", role: .cancel) {
                // Mark as shown so we don't nag the user again
                hasShownAlwaysAlert = true
            }
        } message: {
            Text("For the best experience, VisitedStates needs 'Always' location access to detect state crossings even when the app is closed or the device is restarted.")
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
        let status = dependencies.locationService.authorizationStatus.value
        
        // If this is the first launch and we don't have Always permission,
        // show the alert requesting it (but only once)
        if !hasShownAlwaysAlert && status != .authorizedAlways {
            // Check if we need to show the prompt
            showLocationPermissionAlert = true
        }
    }
}
