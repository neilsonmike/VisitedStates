import SwiftUI
import Combine

@main
struct VisitedStatesApp: App {
    // Connect the AppDelegate to handle location-based app launch
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Create a single AppDependencies instance to manage all services
    @StateObject private var dependencies = AppDependencies.live()
    
    // Track permission request states
    @AppStorage("hasRequestedNotifications") private var hasRequestedNotifications = false
    @AppStorage("hasRequestedLocation") private var hasRequestedLocation = false
    
    // Store the cancellable for notification subscription
    @State private var notificationSubscription: AnyCancellable? = nil
    
    // Track cloud sync status
    @State private var isInitialSyncComplete = false
    @State private var syncInProgress = false
    
    var body: some Scene {
        WindowGroup {
            // Show the IntroMapView directly
            IntroMapView()
                .environmentObject(dependencies)
                .onAppear {
                    print("🟢 App is launching: VisitedStatesApp.swift")
                    
                    // Perform initial cloud sync to ensure data is up to date
                    // This is especially important for fresh installs
                    performInitialCloudSync()
                    
                    // Start the permission sequence
                    if !hasRequestedNotifications {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            requestNotificationsWithCallback()
                        }
                    } else if !hasRequestedLocation {
                        // If notifications were already handled but location wasn't
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            requestLocationPermission()
                        }
                    }
                    
                    // If app was launched by location services, start them
                    if appDelegate.launchedByLocationServices {
                        dependencies.locationService.startLocationUpdates()
                        dependencies.stateDetectionService.startStateDetection()
                        print("✅ Successfully restarted location services after device reboot")
                    }
                }
        }
    }
    
    // Request notifications with a callback to request location after
    private func requestNotificationsWithCallback() {
        print("🔔 Requesting notification permissions first")
        hasRequestedNotifications = true
        
        // Observe notification authorization changes
        notificationSubscription = dependencies.notificationService.isNotificationsAuthorized
            .dropFirst() // Skip the initial value
            .sink { authorized in
                // This will be called after the user has made a decision about notifications
                print("🔔 User responded to notification permission request - authorized: \(authorized)")
                
                // Wait a short delay before showing the location permission
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !hasRequestedLocation {
                        requestLocationPermission()
                    }
                }
                
                // Cancel the subscription since we only need the first response
                notificationSubscription?.cancel()
            }
        
        // Actually request the permission
        dependencies.notificationService.requestNotificationPermissions()
        
        // Set a timeout to cancel subscription if we don't get a response
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            notificationSubscription?.cancel()
        }
    }
    
    private func requestLocationPermission() {
        print("🗺️ Now requesting location permission")
        hasRequestedLocation = true
        
        // FIXED: Use a background thread to call requestWhenInUseAuthorization
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                // Mark that we've requested permission first (on main thread)
                // to avoid potential race conditions
                print("🗺️ Setting hasRequestedLocation flag to true")
            }
            // Then request permission from background thread
            print("🗺️ Dispatching location permission request to background thread")
            DispatchQueue.global().async {
                // This call will itself dispatch to a background thread
                self.dependencies.locationService.requestWhenInUseAuthorization()
            }
        }
    }
    
    // Perform initial cloud sync to ensure data is up to date
    private func performInitialCloudSync() {
        // Prevent multiple syncs
        guard !syncInProgress && !isInitialSyncComplete else { return }
        
        syncInProgress = true
        print("☁️ Performing initial cloud sync on app start")
        
        // Fetch data from CloudKit
        dependencies.cloudSyncService.fetchFromCloud { result in
            syncInProgress = false
            
            switch result {
            case .success(let states):
                print("✅ Initial cloud sync successful - fetched \(states.count) states")
                isInitialSyncComplete = true
                dependencies.notificationService.cloudSyncDidComplete()
                
                // Perform an additional sync to CloudKit with our current data
                // This helps ensure everything is in sync both ways
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    performCloudUpSync()
                }
                
            case .failure(let error):
                print("⚠️ Initial cloud sync failed: \(error.localizedDescription)")
                
                // Retry once after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    syncInProgress = false
                    performRetryCloudSync()
                }
            }
        }
    }
    
    // Retry cloud sync once if the initial sync failed
    private func performRetryCloudSync() {
        guard !syncInProgress && !isInitialSyncComplete else { return }
        
        syncInProgress = true
        print("☁️ Retrying cloud sync...")
        
        dependencies.cloudSyncService.fetchFromCloud { result in
            syncInProgress = false
            
            switch result {
            case .success(let states):
                print("✅ Retry cloud sync successful - fetched \(states.count) states")
                isInitialSyncComplete = true
                
                // Upload any local changes back to the cloud
                performCloudUpSync()
                
            case .failure(let error):
                print("⚠️ Retry cloud sync also failed: \(error.localizedDescription)")
                // Don't attempt further retries to avoid potential loops
            }
        }
    }
    
    // After downloading from cloud, also upload any local states
    private func performCloudUpSync() {
        guard !syncInProgress else { return }
        
        syncInProgress = true
        print("☁️ Syncing local data back to cloud...")
        
        // Get the current states
        let currentStates = dependencies.settingsService.visitedStates.value
        
        dependencies.cloudSyncService.syncToCloud(states: currentStates) { result in
            syncInProgress = false
            
            switch result {
            case .success:
                print("✅ Cloud up-sync successful - sent \(currentStates.count) states")
            case .failure(let error):
                print("⚠️ Cloud up-sync failed: \(error.localizedDescription)")
            }
        }
    }
}
