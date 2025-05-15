import SwiftUI
import Combine
import CoreLocation
import UserNotifications

// No special import needed as FactoidDebugView should be in the same module

struct SettingsView: View {
    // Access app dependencies
    @EnvironmentObject var dependencies: AppDependencies
    
    // Environment values
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.scenePhase) var scenePhase
    
    // Local state
    @State private var showingSchemaAlert: Bool = false
    @State private var showRestoreAlert = false  // For restore defaults confirmation
    @State private var showResetBadgesAlert = false  // For resetting badges confirmation
    @State private var notificationsEnabled = true
    @State private var notifyOnlyNewStates = false
    @State private var stateFillColor: Color = .red
    @State private var stateStrokeColor: Color = .white
    @State private var backgroundColor: Color = .white
    @State private var cancellables = Set<AnyCancellable>()
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    @State private var systemNotificationsAuthorized = false
    @State private var showNotificationSettingsAlert = false
    
    // New state for showing AboutView as sheet
    @State private var showingAboutView = false

    // Track background refresh and precise location status
    @State private var isBackgroundRefreshEnabled = false
    @State private var isPreciseLocationEnabled = true

    // Break up the view to avoid complex type-checking
    @ViewBuilder 
    func settingsContent() -> some View {
        NavigationView {
            Form {
                // Notifications Section - Now as the first section
                Section(header: Text("Notifications")) {
                    // Notification toggle with warning
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Enable Notifications", isOn: $notificationsEnabled)
                            .onChange(of: notificationsEnabled) { _, newValue in
                                dependencies.settingsService.notificationsEnabled.send(newValue)
                                
                                // Check for discrepancy with system settings
                                if newValue && !systemNotificationsAuthorized {
                                    showNotificationSettingsAlert = true
                                }
                                
                                // Sync settings to cloud after change
                                dependencies.cloudSyncService.syncSettingsToCloud(completion: nil)
                            }
                        
                        // Warning indicator when there's a discrepancy
                        if notificationsEnabled && !systemNotificationsAuthorized {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("System notifications are disabled")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(.top, 2)
                        }
                    }
                    
                    if notificationsEnabled {
                        VStack(alignment: .leading) {
                            Toggle("Notify Only for New States", isOn: $notifyOnlyNewStates)
                                .onChange(of: notifyOnlyNewStates) { _, newValue in
                                    dependencies.settingsService.notifyOnlyNewStates.send(newValue)
                                    
                                    // Sync settings to cloud after change
                                    dependencies.cloudSyncService.syncSettingsToCloud(completion: nil)
                                }
                            
                            // Conditional explainer text
                            Text(notifyOnlyNewStates ?
                                 "You will only be notified if you enter a state you have not visited before" :
                                 "You will get a notification whenever you enter any state")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                                .padding(.leading, 4)
                        }
                        
                        // Link to system notification settings at the bottom of this section
                        Button("Open System Notification Settings") {
                            openNotificationSettings()
                        }
                        .foregroundColor(.blue)
                        .padding(.top, 8)
                    }
                }
                
                // Customizations Section
                Section(header: Text("Customizations")) {
                    ColorPicker("State Fill Color", selection: $stateFillColor)
                        .onChange(of: stateFillColor) { _, newValue in
                            dependencies.settingsService.stateFillColor.send(newValue)
                            // Sync settings to cloud after change
                            dependencies.cloudSyncService.syncSettingsToCloud(completion: nil)
                        }
                    
                    ColorPicker("State Border Color", selection: $stateStrokeColor)
                        .onChange(of: stateStrokeColor) { _, newValue in
                            dependencies.settingsService.stateStrokeColor.send(newValue)
                            // Sync settings to cloud after change
                            dependencies.cloudSyncService.syncSettingsToCloud(completion: nil)
                        }
                    
                    ColorPicker("Background Color", selection: $backgroundColor)
                        .onChange(of: backgroundColor) { _, newValue in
                            dependencies.settingsService.backgroundColor.send(newValue)
                            // Sync settings to cloud after change
                            dependencies.cloudSyncService.syncSettingsToCloud(completion: nil)
                        }
                    
                    // Restore Defaults button as part of the Customizations section
                    Button("Restore Defaults") {
                        showRestoreAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                // Location Privacy Section
                Section(header: Text("Location Access")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current Permission:")
                            Spacer()
                            Text(locationStatusText)
                                .foregroundColor(.primary)
                        }
                        
                        // Show contextual message based on current permission
                        if locationStatus == .authorizedAlways {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Optimal setting for state detection")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                            .padding(.top, 2)

                            Text("You have granted 'Always' permission, which allows VisitedStates to detect state crossings even when the app is closed.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)

                            // Add warning about Background App Refresh if disabled
                            if !isBackgroundRefreshEnabled {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Background App Refresh is disabled")
                                            .font(.subheadline)
                                            .foregroundColor(.orange)
                                        Text("For optimal background tracking, please enable Background App Refresh in iOS Settings.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            // Add warning about Precise Location if disabled
                            if !isPreciseLocationEnabled {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Precise Location is disabled")
                                            .font(.subheadline)
                                            .foregroundColor(.orange)
                                        Text("For accurate state border detection, please enable Precise Location in iOS Settings.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } else if locationStatus == .authorizedWhenInUse {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Background detection limited")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                            }
                            .padding(.top, 2)
                            
                            Text("To detect state crossings in the background, VisitedStates needs 'Always' location access. Currently, states will only be detected when the app is open.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                            
                            // Upgrade prompt with clearer iOS limitations explanation
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About 'Always' permission:")
                                    .font(.subheadline)
                                    .bold()

                                Text("Due to Apple's Privacy system, 'Always' location permission must be set manually.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 4)
                                
                                Text("To upgrade to 'Always' permission:")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("1. Tap 'Open iOS Settings' below")
                                        .font(.caption)
                                    Text("2. Scroll down and tap 'VisitedStates'")
                                        .font(.caption)
                                    Text("3. Tap 'Location'")
                                        .font(.caption)
                                    Text("4. Select 'Always'")
                                        .font(.caption)
                                    Text("5. Return to VisitedStates app")
                                        .font(.caption)
                                }
                                .padding(.leading, 8)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            // For denied, restricted, or not determined
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("State detection unavailable")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                            .padding(.top, 2)
                            
                            Text("VisitedStates cannot automatically detect state crossings without location permission. Please grant location access in Settings to enable this feature.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                        }
                        
                        Button(action: {
                            // UIApplication.openSettingsURLString opens directly to this app's settings page
                            // This is the Apple-approved way to deep link to app settings
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
                        }) {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open iOS Settings")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
                
                // About and Debug Section
                Section {
                    Button("About VisitedStates") {
                        showingAboutView = true
                    }

                    // Debug tools - Only show in DEBUG builds
                    #if DEBUG
                    Button("Reset All Badges") {
                        showResetBadgesAlert = true
                    }
                    .foregroundColor(.red)
                    #endif
                }
            }
            .navigationTitle("Settings")
            // Add Done button to navigation bar (right side - iOS standard)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("Notification Settings", isPresented: $showNotificationSettingsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    openNotificationSettings()
                }
            } message: {
                Text("Notifications are enabled in the app but disabled in your device settings. Would you like to update your iOS notification settings?")
            }
            .alert("Restore Defaults", isPresented: $showRestoreAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Restore", role: .destructive) {
                    dependencies.settingsService.restoreDefaults()
                }
            } message: {
                Text("Are you sure you want to restore the default color selections?")
            }
            .alert("Reset All Badges", isPresented: $showResetBadgesAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    // Create a BadgeTrackingService and reset all badges
                    let badgeService = BadgeTrackingService()
                    badgeService.resetAllBadges()
                    print("🏆 All badges have been reset")
                }
            } message: {
                Text("Are you sure you want to reset all badge progress? This will remove all earned badges and cannot be undone.")
            }
            // Present AboutView as sheet instead of NavigationLink
            .sheet(isPresented: $showingAboutView) {
                AboutView()
            }
        }
        .onAppear {
            setupSubscriptions()
            updateLocationStatus()
            checkNotificationStatus()
            checkBackgroundRefreshStatus()
            checkPreciseLocationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Refresh notification status whenever app becomes active again
                checkNotificationStatus()
                
                // Also refresh location status
                updateLocationStatus()

                // Check background refresh and precise location status
                checkBackgroundRefreshStatus()
                checkPreciseLocationStatus()

                print("🔄 App became active - refreshing permissions status")
            }
        }
        .onDisappear {
            // When settings view is dismissed, trigger a sync
            print("SettingsView disappearing - triggering sync")
            dependencies.cloudSyncService.syncToCloud(
                states: dependencies.settingsService.visitedStates.value) { result in
                    switch result {
                    case .success:
                        print("✅ Settings view dismissal sync completed successfully")
                    case .failure(let error):
                        print("❌ Settings view dismissal sync failed: \(error.localizedDescription)")
                    }
                }
            
            cancellables.removeAll()
        }
    }
    
    private var locationStatusText: String {
        switch locationStatus {
        case .authorizedAlways:
            return "Always"
        case .authorizedWhenInUse:
            return "While Using App"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
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
            return .red
        @unknown default:
            return .red
        }
    }
    
    private func updateLocationStatus() {
        // Get the current location authorization status
        locationStatus = dependencies.locationService.authorizationStatus.value
    }
    
    private func setupSubscriptions() {
        // Subscribe to settings changes
        dependencies.settingsService.notificationsEnabled
            .sink { value in
                self.notificationsEnabled = value
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.notifyOnlyNewStates
            .sink { value in
                self.notifyOnlyNewStates = value
            }
            .store(in: &cancellables)
        
        dependencies.settingsService.stateFillColor
            .sink { color in
                self.stateFillColor = color
            }
            .store(in: &cancellables)
        
        dependencies.settingsService.stateStrokeColor
            .sink { color in
                self.stateStrokeColor = color
            }
            .store(in: &cancellables)
        
        dependencies.settingsService.backgroundColor
            .sink { color in
                self.backgroundColor = color
            }
            .store(in: &cancellables)
        
        // Subscribe to location authorization changes
        dependencies.locationService.authorizationStatus
            .sink { status in
                self.locationStatus = status
            }
            .store(in: &cancellables)
            
        // Subscribe to notification authorization status
        dependencies.notificationService.isNotificationsAuthorized
            .sink { isAuthorized in
                self.systemNotificationsAuthorized = isAuthorized
            }
            .store(in: &cancellables)
    }
    
    private func checkNotificationStatus() {
        // Request the current notification status from the service
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let isAuthorized = (settings.authorizationStatus == .authorized ||
                                  settings.authorizationStatus == .provisional)
                
                print("🔔 Checking notification status: \(isAuthorized ? "Authorized" : "Not authorized")")
                self.systemNotificationsAuthorized = isAuthorized
                
                // Also update the service's status
                self.dependencies.notificationService.isNotificationsAuthorized.send(isAuthorized)
            }
        }
    }
    
    private func openNotificationSettings() {
        // UIApplication.openSettingsURLString opens directly to this app's settings page in iOS Settings
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func checkBackgroundRefreshStatus() {
        // Check if background refresh is enabled for the app
        let status = UIApplication.shared.backgroundRefreshStatus
        DispatchQueue.main.async {
            self.isBackgroundRefreshEnabled = (status == .available)
            print("🔄 Background App Refresh status: \(status == .available ? "Enabled" : "Disabled")")
        }
    }

    private func checkPreciseLocationStatus() {
        // Check if precise location is enabled
        let locationManager = CLLocationManager()
        DispatchQueue.main.async {
            self.isPreciseLocationEnabled = locationManager.accuracyAuthorization == .fullAccuracy
            print("📍 Precise Location status: \(locationManager.accuracyAuthorization == .fullAccuracy ? "Enabled" : "Disabled")")
        }
    }
    
    // Define the actual body property that uses our content function
    var body: some View {
        settingsContent()
    }
}
