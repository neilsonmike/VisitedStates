import SwiftUI
import MapKit
import Combine

struct IntroMapView: View {
    @State private var showStates: [String] = []
    @State private var fadeOutIntro = false
    @State private var navigateToMain = false
    @State private var fadeIn = false
    @State private var needsOnboarding = false
    @State private var showLoadingIndicator = false
    
    // Access the app dependencies
    @EnvironmentObject var dependencies: AppDependencies
    
    // Access app-wide cloud status
    @Binding var cloudSyncComplete: Bool
    @Binding var settingsSyncComplete: Bool
    
    // Access app-wide onboarding state
    @AppStorage("hasRequestedNotifications") private var hasRequestedNotifications = false
    @AppStorage("hasRequestedLocation") private var hasRequestedLocation = false
    
    // Default initializer for SwiftUI preview
    init() {
        self._cloudSyncComplete = .constant(true)
        self._settingsSyncComplete = .constant(true)
    }
    
    // Real initializer with bindings
    init(cloudSyncComplete: Binding<Bool>, settingsSyncComplete: Binding<Bool>) {
        self._cloudSyncComplete = cloudSyncComplete
        self._settingsSyncComplete = settingsSyncComplete
    }
    
    private let stateSequence: [String] = [
        "Pennsylvania", "New York", "Ohio", "West Virginia",
        "Maryland", "Virginia", "Kentucky", "Tennessee",
        "North Carolina", "South Carolina", "Georgia", "Indiana",
    ]
    
    private let stateFadeInterval: TimeInterval = 0.15
    private let fadeOutDelay: TimeInterval = 0.3
    private let navigateDelay: TimeInterval = 1.0 // Increased to give time for onboarding check

    var body: some View {
        ZStack {
            // Background - change to use Color.primary.colorInvert() which respects dark mode
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            // State animations
            GeometryReader { geometry in
                Canvas { context, size in
                    for state in showStates {
                        drawState(context: &context, stateName: state, size: size)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(0.3)
            }
            .edgesIgnoringSafeArea(.all)

            // Logo image - explicitly centered
            VStack {
                Spacer()
                
                // Debugging - add a colored background to see if the image area is visible
                Image("VisitedStatesLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: UIScreen.main.bounds.width * 0.7) // 70% of screen width
                    .background(Color.clear) // For debugging - change to a color if needed
                    .opacity(fadeOutIntro ? 0 : 1)
                
                Spacer()
            }
            .animation(.easeOut(duration: 1.5), value: fadeOutIntro)
            
            // Cloud sync loading indicator
            if showLoadingIndicator {
                VStack {
                    Spacer()
                    
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                        
                        Text("Loading your settings...")
                            .font(.system(.headline, design: .rounded))
                            .padding(.leading, 8)
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground).opacity(0.8))
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeIn, value: showLoadingIndicator)
            }
        }
        .opacity(fadeIn ? 1 : 0)
        .animation(.easeIn(duration: 0.6), value: fadeIn)
        .onAppear {
            // Debug log to ensure this view is loaded
            print("IntroMapView appeared - animation will start")
            
            fadeIn = true
            showStates = []
            fadeOutIntro = false
            navigateToMain = false

            startAnimation()
        }
        // First use fullScreenCover for onboarding if needed
        .fullScreenCover(isPresented: $needsOnboarding) {
            OnboardingView(isPresented: $needsOnboarding, isExistingUser: UserDefaults.standard.bool(forKey: "appPreviouslyLaunched"))
                .environmentObject(dependencies)
                .onDisappear {
                    // When onboarding is dismissed normally (not via the direct route)
                    // we'll still navigate to main view for compatibility
                    print("🚀 Onboarding completed - navigating to main view")
                    navigateToMain = true
                }
        }
        // Then use fullScreenCover for main content view
        .fullScreenCover(isPresented: $navigateToMain) {
            ContentView()
                .environmentObject(dependencies)
        }
    }

    private func startAnimation() {
        // Animate the appearance of each state in sequence
        for (index, state) in stateSequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (stateFadeInterval * Double(index))) {
                withAnimation {
                    showStates.append(state)
                }
            }
        }
        
        // Delay before fading out the intro text/logo
        DispatchQueue.main.asyncAfter(deadline: .now() + (stateFadeInterval * Double(stateSequence.count)) + fadeOutDelay) {
            // Debug log to ensure this is triggered
            print("Fading out intro logo")
            withAnimation { fadeOutIntro = true }
            
            // Show loading indicator if cloud sync isn't complete
            if !cloudSyncComplete || !settingsSyncComplete {
                print("⏳ Showing loading indicator while waiting for cloud sync")
                showLoadingIndicator = true
            }
        }
        
        // Wait a bit and then check cloud sync status before continuing
        DispatchQueue.main.asyncAfter(deadline: .now() + (stateFadeInterval * Double(stateSequence.count)) + navigateDelay) {
            // For reinstalls (iCloud data exists), ensure cloud settings are loaded before proceeding
            checkCloudAndProceed()
        }
    }
    
    // Helper method to check cloud status and proceed when ready
    private func checkCloudAndProceed() {
        // Wait for both syncs to complete
        if !cloudSyncComplete || !settingsSyncComplete {
            print("⏳ Waiting for cloud sync to complete before continuing...")
            // Check again after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                checkCloudAndProceed()
            }
            return
        }
        
        // Cloud sync is complete, continue with navigation
        showLoadingIndicator = false
            
        let isExistingUser = UserDefaults.standard.bool(forKey: "appPreviouslyLaunched")
        
        // Simplified logic: Only show onboarding for new users
        if !isExistingUser {
            // New user - always show full onboarding
            print("🆕 New user - showing full onboarding")
            self.needsOnboarding = true
        } else {
            // Existing user - skip onboarding and go straight to main view
            // They can use the badge on settings if they need to change permissions
            print("👤 Existing user - skipping onboarding, going to main view")
            navigateToMain = true
        }
        
        // Mark that the app has been launched
        UserDefaults.standard.set(true, forKey: "appPreviouslyLaunched")
    }

    private func drawState(context: inout GraphicsContext, stateName: String, size: CGSize) {
        // Access the boundary service to get state polygons
        guard let polygons = dependencies.stateBoundaryService.statePolygons[stateName] else { return }

        let boundingBox = computeBoundingBox(for: stateSequence)

        let scaleX = size.width / CGFloat(boundingBox.size.width)
        let scaleY = size.height / CGFloat(boundingBox.size.height)
        let scale = min(scaleX, scaleY)

        let offsetX = (size.width - CGFloat(boundingBox.size.width) * scale) / 2
        let offsetY = (size.height - CGFloat(boundingBox.size.height) * scale) / 2

        func transform(_ point: MKMapPoint) -> CGPoint {
            return CGPoint(
                x: offsetX + CGFloat(point.x - boundingBox.origin.x) * scale,
                y: offsetY + CGFloat(point.y - boundingBox.origin.y) * scale
            )
        }

        // Use gray for the intro animation, but adapt to dark mode
        let fillColor = Color.gray
        let strokeColor = Color(UIColor.systemBackground) // This will be white in light mode and black in dark mode

        for polygon in polygons {
            var path = Path()
            let count = polygon.pointCount
            guard count > 0 else { continue }
            let points = polygon.points()
            let firstPoint = transform(points[0])

            path.move(to: firstPoint)
            for i in 1..<count {
                let point = transform(points[i])
                path.addLine(to: point)
            }
            path.closeSubpath()

            context.fill(path, with: .color(fillColor))
            context.stroke(path, with: .color(strokeColor), lineWidth: 0.5)
        }
    }
    
    private func computeBoundingBox(for states: [String]) -> MKMapRect {
        var boundingBox: MKMapRect?
        for state in states {
            if let polygons = dependencies.stateBoundaryService.statePolygons[state] {
                for polygon in polygons {
                    if boundingBox == nil {
                        boundingBox = polygon.boundingMapRect
                    } else {
                        boundingBox = boundingBox?.union(polygon.boundingMapRect)
                    }
                }
            }
        }
        return boundingBox ?? MKMapRect()
    }
}
