import SwiftUI
import CoreLocation

struct OnboardingView: View {
    // Environment objects
    @EnvironmentObject var dependencies: AppDependencies
    
    // Environment values
    @Environment(\.presentationMode) var presentationMode
    
    // Binding to control visibility from parent
    @Binding var isPresented: Bool
    
    // State variables for tracking onboarding progress
    @State private var currentPage = 0
    @State private var locationPermissionRequested = false
    @State private var notificationPermissionRequested = false
    @State private var showingLocationSettingsInfo = false
    
    // Tracks whether this is an existing user or a new user
    var isExistingUser: Bool
    
    // UserDefaults keys
    private let onboardingCompleteKey = "onboardingCompleteV2" // Updated key for new version
    private let permissionOnboardingShownKey = "permissionOnboardingShown" 
    
    init(isPresented: Binding<Bool>, isExistingUser: Bool = false) {
        self._isPresented = isPresented
        self.isExistingUser = isExistingUser
        
        // For existing users, we start on the location permission page
        // unless they already have optimal permissions
        if isExistingUser {
            _currentPage = State(initialValue: 2) // Start at location permission page
        }
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
                    Button(isExistingUser ? "Return to App" : "Start Exploring") {
                        // Mark onboarding as complete for new users
                        if !isExistingUser {
                            UserDefaults.standard.set(true, forKey: onboardingCompleteKey)
                        }
                        
                        // For both new and existing users, mark that permission explanation has been shown
                        UserDefaults.standard.set(true, forKey: permissionOnboardingShownKey)
                        
                        // Dismiss onboarding
                        isPresented = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.bottom)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingLocationSettingsInfo) {
            LocationSettingsInfoView()
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
            
            Text("VisitedStates needs access to your location in the background to detect when you cross state lines.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 10) {
                LocationPermissionOption(
                    title: "Always",
                    description: "Detects states even when the app is closed",
                    isRecommended: true,
                    isSelected: locationStatus == .authorizedAlways
                )
                
                LocationPermissionOption(
                    title: "While Using App",
                    description: "Only detects states when the app is open",
                    isRecommended: false,
                    isSelected: locationStatus == .authorizedWhenInUse
                )
                
                LocationPermissionOption(
                    title: "Never",
                    description: "You'll need to add states manually",
                    isRecommended: false,
                    isSelected: locationStatus == .denied || locationStatus == .restricted
                )
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            if locationStatus == .authorizedWhenInUse {
                Button("How to Enable 'Always' Access") {
                    showingLocationSettingsInfo = true
                }
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(.blue)
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
            
            // Settings info
            Text("You can change these settings later in the app's Settings page or in your device Settings.")
                .font(.system(.footnote, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.top)
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
                dependencies.locationService.requestWhenInUseAuthorization()
            } else {
                withAnimation {
                    currentPage += 1
                }
            }
        case "notificationPermission":
            if !notificationPermissionRequested {
                notificationPermissionRequested = true
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    
                    if isRecommended {
                        Text("Recommended")
                            .font(.system(.caption, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                
                Text(description)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                .font(.title2)
        }
        .padding(.vertical, 8)
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