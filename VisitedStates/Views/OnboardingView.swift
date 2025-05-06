import SwiftUI
import CoreLocation

struct OnboardingView: View {
    // Environment objects
    @EnvironmentObject var dependencies: AppDependencies
    
    // Environment values
    @Environment(\.presentationMode) var presentationMode
    
    // Binding to control visibility from parent
    @Binding var isPresented: Bool
    
    // Add a state to control direct navigation to ContentView
    @State private var showContentView = false
    
    // State variables for tracking onboarding progress
    @State private var currentPage = 0
    @State private var locationPermissionRequested = false
    @State private var notificationPermissionRequested = false
    @State private var showingLocationSettingsInfo = false
    @State private var showAlwaysAccessButton = false
    @State private var lastPermissionRequestTime = Date()
    
    // Tracks whether this is an existing user or a new user
    var isExistingUser: Bool
    
    // UserDefaults keys
    private let onboardingCompleteKey = "onboardingCompleteV2" // Updated key for new version
    private let permissionOnboardingShownKey = "permissionOnboardingShown" 
    
    init(isPresented: Binding<Bool>, isExistingUser: Bool = false) {
        self._isPresented = isPresented
        self.isExistingUser = isExistingUser
        
        // Always start at the welcome page - we won't show onboarding to existing users at all,
        // so this code is now simplified. The IntroMapView will only show onboarding to new users.
        _currentPage = State(initialValue: 0) // Start at welcome page
        
        // Initialize with no auto-prompts
        _showAlwaysAccessButton = State(initialValue: false)
        _showingLocationSettingsInfo = State(initialValue: false)
    }
    
    // Computed properties for permissions status
    private var locationStatus: CLAuthorizationStatus {
        dependencies.locationService.authorizationStatus.value
    }
    
    private var notificationsEnabled: Bool {
        dependencies.notificationService.isNotificationsAuthorized.value
    }
    
    // Pages in the onboarding flow
    let pages = [
        "welcome",        // Welcome screen
        "valueProposition", // Value prop screen
        "locationPermission", // Location permission explanation
        "notificationPermission", // Notification permission explanation
        "setupComplete"   // Completion screen
    ]
    
    var body: some View {
        ZStack {
            // Background color that matches the app
            Color(uiColor: UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                // Progress indicator
                if currentPage > 0 && currentPage < pages.count - 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<pages.count - 1, id: \.self) { index in
                            Circle()
                                .fill(currentPage > index ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top)
                }
                
                Spacer()
                
                // Page content
                switch pages[currentPage] {
                case "welcome":
                    welcomePage
                case "valueProposition":
                    valuePropositionPage
                case "locationPermission":
                    locationPermissionPage
                case "notificationPermission":
                    notificationPermissionPage
                case "setupComplete":
                    setupCompletePage
                default:
                    EmptyView()
                }
                
                Spacer()
                
                // Navigation buttons
                if currentPage == 0 {
                    Button("Get Started") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.bottom)
                } else if currentPage < pages.count - 1 {
                    HStack {
                        Button("Back") {
                            withAnimation {
                                currentPage -= 1
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        
                        Spacer()
                        
                        Button(getNextButtonText()) {
                            handleNextButton()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                } else {
                    Button("Let's Go!") {
                        // Mark onboarding as complete for new users
                        if !isExistingUser {
                            UserDefaults.standard.set(true, forKey: onboardingCompleteKey)
                        }
                        
                        // For both new and existing users, mark that permission explanation has been shown
                        UserDefaults.standard.set(true, forKey: permissionOnboardingShownKey)
                        
                        // IMPORTANT: Go directly to ContentView without going back to IntroMapView
                        showContentView = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.bottom)
                }
            }
            .padding()
        }
        // Direct fullScreenCover to ContentView (skipping IntroMapView altogether)
        .fullScreenCover(isPresented: $showContentView) {
            ContentView()
                .environmentObject(dependencies)
        }
    }
    
    // MARK: - Page Views
    
    // Welcome screen
    var welcomePage: some View {
        VStack(spacing: 20) {
            // App logo
            Image("VisitedStatesLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 150)
            
            Text("Welcome to VisitedStates")
                .font(.system(.largeTitle, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
            
            Text("Automatically track and remember the states you've visited as you travel")
                .font(.system(.title3, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    // Value proposition screen
    var valuePropositionPage: some View {
        VStack(spacing: 30) {
            Text("Your Personal Travel Map")
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    iconName: "location.fill",
                    title: "Automatic Detection",
                    description: "Cross a state line and we'll log it for you - even when your phone is asleep"
                )
                
                FeatureRow(
                    iconName: "bell.fill",
                    title: "Instant Notifications",
                    description: "Get notified the moment you enter a new state"
                )
                
                FeatureRow(
                    iconName: "map.fill",
                    title: "Beautiful Maps",
                    description: "See your visited states highlighted on a customizable map"
                )
                
                FeatureRow(
                    iconName: "square.and.arrow.up.fill",
                    title: "Easy Sharing",
                    description: "Share your travel map with friends and family"
                )
            }
            .padding(.horizontal)
        }
    }
    
    // Location permission explanation
    var locationPermissionPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            Text("Location Access")
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
            
            Text("Location access lets us track the states you visit.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 10) {
                // Only show options the user can actually select at this stage
                LocationPermissionOption(
                    title: "While Using App",
                    description: "Track states when app is open",
                    isRecommended: true, // Now the recommended option for initial setup
                    isSelected: locationStatus == .authorizedWhenInUse
                )
                
                LocationPermissionOption(
                    title: "Don't Allow",
                    description: "Add states manually",
                    isRecommended: false,
                    isSelected: locationStatus == .denied || locationStatus == .restricted
                )
                
                // Add note about "Always" option
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .padding(.top, 2)
                    
                    Text("For best experience, visit Settings after setup to enable 'Always' permission.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true) // Forces text to wrap
                }
                .padding(.top, 8)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // We're completely removing the automatic "Always" access option from the onboarding flow
        // Users can find this information in the Settings screen after completing onboarding
        }
        // Set up this screen
        .onAppear {
            // No automatic prompts for 'Always' permission during onboarding
            showingLocationSettingsInfo = false
            showAlwaysAccessButton = false
        }
        // Monitor when app becomes active again (returning from Settings)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Force UI refresh by triggering objectWillChange
            let currentStatus = dependencies.locationService.authorizationStatus.value
            print("📍 Returned to onboarding - Location status: \(currentStatus)")
            
            // Force view update - we need to use StateObject to trigger a view update
            // Here we use a simpler approach just to force the view to refresh
            withAnimation {
                // Toggling any @State property will cause view to refresh
                showingLocationSettingsInfo = false
                showAlwaysAccessButton = false
            }
        }
    }
    
    // Notification permission explanation
    var notificationPermissionPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            Text("Stay Informed")
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
            
            Text("Get notified when you enter a new state!")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading) {
                        Text("Know instantly when you cross a state line")
                            .font(.system(.headline, design: .rounded))
                        Text("Perfect for road trips and travel")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading) {
                        Text("Never miss a state you've visited")
                            .font(.system(.headline, design: .rounded))
                        Text("Even when your phone is in your pocket")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Show notification status
            HStack {
                Image(systemName: notificationsEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(notificationsEnabled ? .green : .red)
                
                Text(notificationsEnabled ? "Notifications are enabled" : "Notifications are disabled")
                    .font(.system(.footnote, design: .rounded))
            }
            .padding(.top)
        }
    }
    
    // Setup complete screen
    var setupCompletePage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.green)
            
            Text("You're All Set!")
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
            
            Text("Your app is configured and ready to use.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Status summary
            VStack(spacing: 15) {
                PermissionStatusRow(
                    title: "Location Access",
                    status: locationStatusText,
                    statusColor: locationStatusColor
                )
                
                PermissionStatusRow(
                    title: "Notifications",
                    status: notificationsEnabled ? "Enabled" : "Disabled",
                    statusColor: notificationsEnabled ? .green : .red
                )
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Add note about Always permissions if they have when in use
            if locationStatus == .authorizedWhenInUse {
                VStack(spacing: 6) {
                    Text("Need background tracking?")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("To track states when app is closed, enable 'Always' access in Settings.")
                        .font(.system(.caption, design: .rounded))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Add upgrade button if they have "When In Use" but not "Always" permission
            if locationStatus == .authorizedWhenInUse {
                Button(action: {
                    // UIApplication.openSettingsURLString opens directly to this app's settings page
                    // This is the Apple-approved way to link to app settings
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14))
                        
                        Text("Enable 'Always' in Settings")
                            .font(.system(.subheadline, design: .rounded))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
                .padding(.top, 8)
            }
            
            // Settings info
            Text("Settings can be changed anytime in the app.")
                .font(.system(.caption, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }
    
    // MARK: - Helper functions
    
    // Get the appropriate button text based on the current page
    private func getNextButtonText() -> String {
        switch pages[currentPage] {
        case "locationPermission":
            return locationPermissionRequested ? "Continue" : "Request Access"
        case "notificationPermission":
            return notificationPermissionRequested ? "Continue" : "Enable Notifications"
        default:
            return "Next"
        }
    }
    
    // Handle next button tap based on the current page
    private func handleNextButton() {
        switch pages[currentPage] {
        case "locationPermission":
            if !locationPermissionRequested {
                locationPermissionRequested = true
                lastPermissionRequestTime = Date()
                
                // Mark that we've explicitly requested location permission through onboarding
                UserDefaults.standard.set(true, forKey: "hasRequestedLocation")
                dependencies.locationService.requestWhenInUseAuthorization()
                
                // NO automatic prompts for "Always" permissions - user can handle that in Settings later
            } else {
                withAnimation {
                    currentPage += 1
                }
            }
        case "notificationPermission":
            if !notificationPermissionRequested {
                notificationPermissionRequested = true
                // Mark that we've explicitly requested notification permission through onboarding
                UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
                dependencies.notificationService.requestNotificationPermissions()
            } else {
                withAnimation {
                    currentPage += 1
                }
            }
        default:
            withAnimation {
                currentPage += 1
            }
        }
    }
    
    // Helper computed properties for location status
    private var locationStatusText: String {
        switch locationStatus {
        case .authorizedAlways:
            return "Always (Optimal)"
        case .authorizedWhenInUse:
            return "While Using App"
        case .denied, .restricted:
            return "Denied"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var locationStatusColor: Color {
        switch locationStatus {
        case .authorizedAlways:
            return .green
        case .authorizedWhenInUse:
            return .orange
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .gray
        @unknown default:
            return .gray
        }
    }
}

// MARK: - Helper Views

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 30)
            .background(Color.blue)
            .foregroundColor(.white)
            .font(.system(.headline, design: .rounded))
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .foregroundColor(.blue)
            .font(.system(.headline, design: .rounded))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct FeatureRow: View {
    let iconName: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: iconName)
                .font(.title)
                .frame(width: 30)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                
                Text(description)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LocationPermissionOption: View {
    let title: String
    let description: String
    let isRecommended: Bool
    let isSelected: Bool
    
    var body: some View {
        HStack(alignment: .top) {
            // Left side - Text content
            VStack(alignment: .leading, spacing: 2) {
                // Title row
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if isRecommended {
                        Text("Best")
                            .font(.system(.caption2, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(3)
                    }
                }
                
                // Description
                Text(description)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            
            Spacer()
            
            // Right side - Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                .font(.body)
                .frame(width: 20)
        }
        .padding(.vertical, 6)
    }
}

struct PermissionStatusRow: View {
    let title: String
    let status: String
    let statusColor: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(.headline, design: .rounded))
            
            Spacer()
            
            Text(status)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(statusColor)
        }
        .padding(.vertical, 4)
    }
}

// Helper view to explain how to enable "Always" location access
struct LocationSettingsInfoView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("How to Enable 'Always' Location Access")
                        .font(.system(.title2, design: .rounded))
                        .bold()
                        .padding(.top)
                    
                    Text("For optimal state detection, VisitedStates needs 'Always' location access. Here's how to enable it:")
                        .font(.system(.body, design: .rounded))
                    
                    VStack(alignment: .leading, spacing: 15) {
                        InstructionStep(
                            number: 1,
                            title: "Open your device Settings",
                            description: "Exit this app and open the Settings app"
                        )
                        
                        InstructionStep(
                            number: 2,
                            title: "Find VisitedStates",
                            description: "Scroll down to find and tap on VisitedStates in the apps list"
                        )
                        
                        InstructionStep(
                            number: 3,
                            title: "Location Settings",
                            description: "Tap on 'Location' and select 'Always'"
                        )
                        
                        InstructionStep(
                            number: 4,
                            title: "Return to VisitedStates",
                            description: "You're all set! The app can now detect states even in the background"
                        )
                    }
                    
                    Text("Note: You'll still be able to use the app with 'While Using' permission, but state detection will only work when the app is open.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
                .padding()
            }
            .navigationBarTitle("Location Settings", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                
                Text("\(number)")
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                
                Text(description)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}