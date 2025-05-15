import Foundation
import CoreLocation
import Combine
import UIKit
import SwiftUI

class StateDetectionService: StateDetectionServiceProtocol {
    // MARK: - Properties
    
    var currentDetectedState = CurrentValueSubject<String?, Never>(nil)
    
    // Dependencies
    private let locationService: LocationServiceProtocol
    private let boundaryService: StateBoundaryServiceProtocol
    private let settings: SettingsServiceProtocol
    private let cloudSync: CloudSyncServiceProtocol
    private let notificationService: NotificationServiceProtocol
    
    // Private state
    private var cancellables = Set<AnyCancellable>()
    private var processingQueue = DispatchQueue(label: "com.neils.VisitedStates.stateDetection", qos: .utility)
    private var isDetecting = false
    private var cachedApplicationState: UIApplication.State = .active
    private var didJustEnterForeground = false
    
    // State detection parameters
    private var consecutiveFailedDetections = 0
    private let maxConsecutiveFailedDetections = 3
    private var lastLocationByState: [String: CLLocation] = [:]
    private var pendingAirportDetections: [String: Date] = [:]
    private var lastProcessedLocation: CLLocation?
    private var stateDetectionCache: [String: Date] = [:]
    private let stateCacheDuration: TimeInterval = 3600 * 24 // 24 hours
    private let minimumDistanceForNewDetection: CLLocationDistance = 50 // Reduced for testing
    private var lastStateUpdateTime: Date? // Track when state was last updated
    
    // MARK: - Initialization
    
    init(
        locationService: LocationServiceProtocol,
        boundaryService: StateBoundaryServiceProtocol,
        settings: SettingsServiceProtocol,
        cloudSync: CloudSyncServiceProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.locationService = locationService
        self.boundaryService = boundaryService
        self.settings = settings
        self.cloudSync = cloudSync
        self.notificationService = notificationService
        
        print("🚀 StateDetectionService initialized")
        setupSubscriptions()
        setupAppStateObservers()
    }
    
    deinit {
        // Clean up notification observers
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
        print("💀 StateDetectionService deinitialized")
    }
    
    // Setup app state observers
    private func setupAppStateObservers() {
        // Store initial app state
        if Thread.isMainThread {
            cachedApplicationState = UIApplication.shared.applicationState
        } else {
            DispatchQueue.main.sync {
                cachedApplicationState = UIApplication.shared.applicationState
            }
        }
        
        // Register for foreground/background notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, 
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        cachedApplicationState = .background
        didJustEnterForeground = false
        print("🔄 StateDetectionService: App did enter background")
    }
    
    @objc private func appDidBecomeActive() {
        cachedApplicationState = .active
        didJustEnterForeground = true
        print("🔄 StateDetectionService: App did become active")
        
        // Check if we have a recently detected state to temporarily suppress
        if let currentState = currentDetectedState.value {
            // Check what the last notified state was from UserDefaults
            let lastNotifiedState = UserDefaults.standard.string(forKey: "lastNotifiedState")
            print("🔄 StateDetectionService: Current detected state on app activation: \(currentState)")
            print("🔄 StateDetectionService: Last notified state from UserDefaults: \(lastNotifiedState ?? "none")")
            
            // Log if they match - this would indicate a potential duplicate
            if currentState == lastNotifiedState {
                print("⚠️ StateDetectionService: POTENTIAL DUPLICATE DETECTED - current state matches last notified state")
            }
        }
        
        // Record that the app became active - use a plain timestamp as a marker
        UserDefaults.standard.set(true, forKey: "didJustBecomeActive")
        
        // Create a timer to reset the flag after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.didJustEnterForeground = false
            UserDefaults.standard.removeObject(forKey: "didJustBecomeActive")
            print("🔄 StateDetectionService: Reset foreground transition flag")
        }
    }
    
    // MARK: - StateDetectionServiceProtocol
    
    func startStateDetection() {
        guard !isDetecting else { return }
        isDetecting = true
        
        print("🗺️ Starting state detection")
        
        // FIXED: We need to properly handle thread safety here
        // First update UI immediately
        DispatchQueue.main.async {
            print("🗺️ Started state detection") // UI log
        }
        
        // Then start location updates on a background thread
        // But don't access UIKit APIs directly from this thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.locationService.startLocationUpdates()
        }
    }
    
    func stopStateDetection() {
        guard isDetecting else { return }
        isDetecting = false
        
        // Stop location updates on the main thread
        DispatchQueue.main.async { [weak self] in
            self?.locationService.stopLocationUpdates()
            print("🗺️ Stopped state detection")
        }
    }
    
    func processLocation(_ location: CLLocation) {
        print("🧩 Processing location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // Create a background task for this processing
        let bgTask = beginBackgroundTask()
        
        // For significant location changes in background, we want to process all of them
        // So we'll skip the distance check that was previously used
        
        // Update last processed location
        self.lastProcessedLocation = location
        
        // Detect the state for this location
        if let stateName = self.detectStateWithFallbacks(for: location) {
            print("🧩 Detected state: \(stateName)")
            
            // Update the current detected state (on main thread)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    // End the background task if self no longer exists
                    self?.endBackgroundTask(bgTask)
                    return
                }
                
                // Get current state before updating
                let previousState = self.currentDetectedState.value
                
                // Only send if the state has changed
                if previousState != stateName {
                    print("✨ NEW STATE DETECTED: \(stateName) (previous: \(previousState ?? "none"))")
                    self.lastStateUpdateTime = Date()
                    self.currentDetectedState.send(stateName)
                    
                    // CORRECTED NOTIFICATION LOGIC:
                    // Only suppress notifications if the app just became active AND 
                    // this state matches the last state we notified about
                    let lastNotifiedState = UserDefaults.standard.string(forKey: "lastNotifiedState")
                    
                    // Debug log regardless of what we decide
                    if self.didJustEnterForeground {
                        print("🔍 App just returned to foreground, current state: \(stateName)")
                        print("🔔 DEBUG: Last notified state in UserDefaults: \(lastNotifiedState ?? "none")")
                    }
                    
                    if self.didJustEnterForeground && lastNotifiedState == stateName {
                        // Only suppress notifications if this is the SAME state that was last notified
                        print("🔕 Suppressing duplicate notification - app just returned to foreground with SAME last notified state: \(stateName)")
                    } else {
                        // Notify about all other state changes
                        print("🔔 Sending notification for \(stateName) - new state or not a duplicate")
                        self.notifyStateChange(stateName)
                    }
                }
                
                // Keep track of last known location in this state
                self.lastLocationByState[stateName] = location
                
                // Store detection time for caching
                self.stateDetectionCache[stateName] = Date()
                
                // IMPORTANT: Add to visited states AFTER notification decision
                // This ensures proper "new state" detection for notifications
                self.settings.addStateViaGPS(stateName)
                
                // Track state visit timestamp for badge achievements
                let badgeService = BadgeTrackingService()
                badgeService.trackStateVisit(stateName)
                
                // Sync with cloud
                self.syncToCloud()
                
                // End the background task
                self.endBackgroundTask(bgTask)
            }
        } else {
            // Increment failed detection counter
            self.consecutiveFailedDetections += 1
            print("❌ Failed to detect state (\(self.consecutiveFailedDetections)/\(self.maxConsecutiveFailedDetections))")
            
            // If we have multiple consecutive failures, try fallback methods
            if self.consecutiveFailedDetections >= self.maxConsecutiveFailedDetections {
                print("🧩 Trying fallback detection methods...")
                self.tryFallbackStateDetection(for: location)
                self.consecutiveFailedDetections = 0
            }
            
            // End the background task
            endBackgroundTask(bgTask)
        }
    }
    
    // MARK: - Private methods
    
    private func setupSubscriptions() {
        // Process new locations as they come in
        locationService.currentLocation
            .compactMap { $0 } // Filter out nil values
            .sink { [weak self] location in
                print("📍 Got new location from service: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                self?.processLocation(location)
            }
            .store(in: &cancellables)
        
        // React to authorization changes
        locationService.authorizationStatus
            .sink { [weak self] status in
                print("🔑 Location authorization status changed: \(status)")
                
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    // Only start location updates if we have set the flag to indicate
                    // the user has gone through the onboarding flow
                    let hasRequestedLocation = UserDefaults.standard.bool(forKey: "hasRequestedLocation")
                    if self?.isDetecting == true && hasRequestedLocation {
                        // Start on background thread but don't access UI APIs directly
                        DispatchQueue.global(qos: .userInitiated).async {
                            self?.locationService.startLocationUpdates()
                        }
                    } else {
                        print("🔑 Got authorization but isDetecting=\(String(describing: self?.isDetecting)) or hasRequestedLocation=\(hasRequestedLocation)")
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func detectStateWithFallbacks(for location: CLLocation) -> String? {
        // Reset failed detection counter if we get a successful detection
        consecutiveFailedDetections = 0
        
        // Primary detection method - using boundary service
        if let stateName = boundaryService.stateName(for: location.coordinate) {
            print("🧩 Primary detection succeeded: \(stateName)")
            return stateName
        } else {
            print("❌ Primary state detection method failed")
        }
        
        // Check if we're dealing with a potential airport arrival
        if let airportState = checkForAirportArrival(location) {
            print("✈️ Detected potential airport arrival in: \(airportState)")
            return airportState
        }
        
        // Return nil if all detection methods failed
        return nil
    }
    
    private func checkForAirportArrival(_ location: CLLocation) -> String? {
        // This function helps detect cases where someone flies into a state
        // by looking for discontinuous location jumps
        
        // If we have no previous locations, we can't detect jumps
        guard !lastLocationByState.isEmpty else {
            return nil
        }
        
        // Find the closest previous state based on time, not distance
        let recentStates = stateDetectionCache.filter {
            $0.value.timeIntervalSinceNow > -24 * 3600 // States detected in the last 24 hours
        }
        
        // If no recent states, can't use this method
        if recentStates.isEmpty {
            return nil
        }
        
        // Try to detect the current state directly
        if let directState = boundaryService.stateName(for: location.coordinate) {
            // Check if this is a significant jump from the previous state's location
            if let previousState = currentDetectedState.value,
               let previousLocation = lastLocationByState[previousState],
               previousState != directState {
                
                let distance = location.distance(from: previousLocation)
                // If distance is large (>100km) and we have a direct state detection,
                // this might be an airport arrival
                if distance > 100000 { // 100km
                    print("✈️ Detected potential airport arrival in \(directState) - distance jump of \(Int(distance/1000))km")
                    
                    // Store the pending detection
                    pendingAirportDetections[directState] = Date()
                    
                    // Wait for a confirming detection within the next few minutes
                    // We'll confirm this in future location updates
                    
                    return directState
                }
            }
        }
        
        // Check if we have any pending airport detections to confirm
        for (state, timestamp) in pendingAirportDetections {
            // If the detection is too old, remove it
            if timestamp.timeIntervalSinceNow < -600 { // 10 minutes
                pendingAirportDetections.removeValue(forKey: state)
                continue
            }
            
            // Try to detect current state
            if let currentState = boundaryService.stateName(for: location.coordinate),
               currentState == state {
                // Confirm the airport detection
                print("✅ Confirmed airport arrival in \(state)")
                pendingAirportDetections.removeValue(forKey: state)
                return state
            }
        }
        
        return nil
    }
    
    private func tryFallbackStateDetection(for location: CLLocation) {
        // This function tries additional methods when the primary detection fails
        print("🔍 Trying fallback state detection methods")
        
        // Method 1: Expand search radius
        if let stateFromExpandedSearch = tryExpandedRadiusSearch(location) {
            print("✅ Expanded radius search found state: \(stateFromExpandedSearch)")
            updateDetectedState(stateFromExpandedSearch)
            return
        }
        
        // Method 2: Check for recent nearby detections
        if let stateFromRecentDetection = tryRecentNearbyDetection(location) {
            print("✅ Recent nearby detection found state: \(stateFromRecentDetection)")
            updateDetectedState(stateFromRecentDetection)
            return
        }
        
        // If all fallbacks fail, log the issue
        print("❌ All fallback state detection methods failed for location: \(location.coordinate)")
    }
    
    private func tryExpandedRadiusSearch(_ location: CLLocation) -> String? {
        // Try detecting the state by checking points in a grid around the current location
        let distanceSteps = [0.01, 0.02, 0.05] // Approximately 1km, 2km, 5km
        
        for distanceDegrees in distanceSteps {
            // Check in a 3x3 grid around the current point
            for latOffset in [-distanceDegrees, 0, distanceDegrees] {
                for lonOffset in [-distanceDegrees, 0, distanceDegrees] {
                    // Skip the center point (already checked in primary detection)
                    if latOffset == 0 && lonOffset == 0 {
                        continue
                    }
                    
                    let testCoordinate = CLLocationCoordinate2D(
                        latitude: location.coordinate.latitude + latOffset,
                        longitude: location.coordinate.longitude + lonOffset
                    )
                    
                    print("🔍 Checking expanded grid point: \(testCoordinate.latitude), \(testCoordinate.longitude)")
                    
                    if let stateName = boundaryService.stateName(for: testCoordinate) {
                        print("✅ Expanded radius search found state: \(stateName)")
                        return stateName
                    }
                }
            }
        }
        
        return nil
    }
    
    private func tryRecentNearbyDetection(_ location: CLLocation) -> String? {
        // Look for recently detected states within a reasonable distance
        let maxDistance: CLLocationDistance = 10000 // 10km
        let maxTimeInterval: TimeInterval = 3600 // 1 hour
        
        // Create an array of tuples with state and distance
        var stateDistances: [(state: String, distance: CLLocationDistance)] = []
        
        for (state, lastLocation) in lastLocationByState {
            let distance = location.distance(from: lastLocation)
            if distance <= maxDistance {
                // Check if this state was detected recently
                if let detectionTime = stateDetectionCache[state],
                   detectionTime.timeIntervalSinceNow > -maxTimeInterval {
                    stateDistances.append((state, distance))
                    print("🔍 Recent state within range: \(state) at \(Int(distance))m")
                }
            }
        }
        
        // If we found any recent nearby states, choose the closest one
        if !stateDistances.isEmpty {
            let closestState = stateDistances.sorted { $0.distance < $1.distance }.first!.state
            print("✅ Recent nearby detection found closest state: \(closestState)")
            return closestState
        }
        
        return nil
    }
    
    private func updateDetectedState(_ state: String) {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            
            // Only update if state has changed
            if strongSelf.currentDetectedState.value != state {
                print("✨ NEW STATE DETECTED (fallback): \(state) (previous: \(strongSelf.currentDetectedState.value ?? "none"))")
                strongSelf.currentDetectedState.send(state)
                
                // Always notify about state detection if state changed
                strongSelf.notifyStateChange(state)
            }
            
            // Add using GPS method since this was detected via location - AFTER notification
            strongSelf.settings.addStateViaGPS(state)
            
            // Track state visit timestamp for badge achievements
            let badgeService = BadgeTrackingService()
            badgeService.trackStateVisit(state)
            
            strongSelf.syncToCloud()
        }
    }
    
    // Minimum time between notifications to prevent overload (30 seconds)
    private let notificationDebounceInterval: TimeInterval = 30
    
    private func notifyStateChange(_ state: String) {
        // Always notify about state changes, even for previously visited states
        // This is the single control point for notifications - BEFORE adding to visited states
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            
            // Debouncing: Check if we've sent a notification recently
            let now = Date()
            if let lastUpdate = strongSelf.lastStateUpdateTime {
                let timeElapsed = now.timeIntervalSince(lastUpdate)
                
                // If less than debounce interval has passed, skip this notification
                if timeElapsed < strongSelf.notificationDebounceInterval {
                    print("🧩 Skipping notification for \(state) - too soon after previous notification (\(Int(timeElapsed))s < \(Int(strongSelf.notificationDebounceInterval))s)")
                    return
                }
            }
            
            // Update last notification time
            strongSelf.lastStateUpdateTime = now
            
            print("🗺️ Notifying about state entry: \(state)")
            
            // Initiate the factoid fetch but don't wait for result yet
            strongSelf.notificationService.handleDetectedState(state)
            
            // Use a short delay for API completion - only 1 second to not be noticeable
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Check for badge achievements with the real badge logic
                strongSelf.triggerBadgeNotification(for: state)
            }
        }
    }

    // Trigger a state notification with earned badges
    private func triggerBadgeNotification(for state: String) {
        print("🏆 Triggering notification for \(state)")
        
        // Check if we should suppress notifications for already visited states
        let isNewState = !settings.hasVisitedState(state)
        let notifyOnlyNewStates = settings.notifyOnlyNewStates.value
        
        // If notify only new states is enabled and this isn't a new state,
        // skip the notifications but still process badges
        let shouldSuppressNotification = notifyOnlyNewStates && !isNewState
        
        if shouldSuppressNotification {
            print("🔕 Suppressing notification for already visited state: \(state) (notify only new states is enabled)")
        } else {
            // CRITICAL: Schedule the system notification first (for background operation)
            // This needs to be done before the in-app notification
            if let notificationService = self.notificationService as? NotificationService {
                // Schedule the system notification via UNUserNotificationCenter
                notificationService.scheduleStateEntryNotification(for: state)
            }
        }

        // IMPORTANT: Use only GPS-verified states for badges
        let gpsVerifiedStates = settings.getActiveGPSVerifiedStates().map { $0.stateName }

        // Get factoid for the state - following proper priority
        var factoid: String? = nil

        // First check for a direct factoid from UserDefaults (set by Google Sheets)
        // This is our highest priority - a fresh Google Sheets result stored directly
        let directFactoidKey = "DIRECT_FACTOID_\(state)"
        if let directFactoid = UserDefaults.standard.string(forKey: directFactoidKey) {
            factoid = directFactoid

            // Clear this one-time factoid once we've used it
            UserDefaults.standard.removeObject(forKey: directFactoidKey)
            UserDefaults.standard.synchronize()
        }
        // Second priority: cached factoid from previous Google Sheets calls
        else if let notificationService = self.notificationService as? NotificationService {
            factoid = notificationService.getCachedFactoid(for: state)
        }

        // No third priority - if no factoid is found, it will remain nil

        // Create badge service instance
        let badgeService = BadgeTrackingService()

        // Check for newly earned badges - ONLY using GPS-verified states
        let newlyEarnedBadges = badgeService.checkForNewBadges(
            allBadges: AchievementBadgeProvider.allBadges,
            visitedStates: gpsVerifiedStates // Use GPS states only
        )

        // Check for special cases to suppress the notification
        let didJustBecomeActive = UserDefaults.standard.bool(forKey: "didJustBecomeActive")
        let lastNotifiedState = UserDefaults.standard.string(forKey: "lastNotifiedState")
        
        // Handle duplicate suppression (app became active with already notified state)
        let skipDueToDuplicate = didJustBecomeActive && lastNotifiedState == state
        
        // Handle suppression due to "notify only new states" setting
        let skipDueToAlreadyVisited = shouldSuppressNotification
        
        // Combined skip flag - suppresses notification unless badges were earned
        let skipStateNotification = (skipDueToDuplicate || skipDueToAlreadyVisited)
        
        // If we should skip the notification and there are no badges, exit completely
        if skipStateNotification && newlyEarnedBadges.isEmpty {
            if skipDueToDuplicate {
                print("🏆 Skipping notification - app just became active and state was already notified")
            } else {
                print("🏆 Skipping notification - already visited state and notify only new states is enabled")
            }
            return
        }

        // Prepare notification contents
        var notification: [String: Any] = [:]

        if !skipStateNotification {
            // Normal case: Include state information
            notification["state"] = state
            if let factoid = factoid {
                notification["factoid"] = factoid
            }
        } else if !newlyEarnedBadges.isEmpty {
            // Special case: Skip state welcome, but show badge notification
            // only if there are badges to show
            notification["state"] = state
            notification["skipWelcome"] = true
        }

        // Add badges if any were earned
        if !newlyEarnedBadges.isEmpty {
            notification["badges"] = newlyEarnedBadges

            // If there are more badges than we can reasonably display,
            // include a total count to show "and X more" text
            if newlyEarnedBadges.count > 3 {
                notification["totalBadgeCount"] = newlyEarnedBadges.count
            }
        }

        // Only post notification if we have something to show
        if !notification.isEmpty {
            // Post notification for real-time display
            NotificationCenter.default.post(
                name: NSNotification.Name("StateDetectionWithBadges"),
                object: nil,
                userInfo: notification
            )
        }
    }
    
    private func syncToCloud() {
        print("☁️ Syncing states to cloud...")
        
        // Create background task for cloud sync
        let syncTask = beginBackgroundTask()
        
        // Sync with cloud with retry logic
        var retryCount = 0
        let maxRetries = 3
        
        func attemptSync() {
            // Get the active states to sync (this is compatible with the current CloudSync implementation)
            let statesToSync = self.settings.visitedStates.value
            
            self.cloudSync.syncToCloud(states: statesToSync) { [weak self] result in
                guard let self = self else {
                    self?.endBackgroundTask(syncTask)
                    return
                }
                
                switch result {
                case .success:
                    print("✅ Successfully synced states to cloud")
                    self.endBackgroundTask(syncTask)
                    
                case .failure(let error):
                    retryCount += 1
                    print("❌ Failed to sync states to cloud: \(error.localizedDescription)")
                    
                    // Retry with exponential backoff
                    if retryCount < maxRetries {
                        let delay = Double(pow(2.0, Double(retryCount))) // 2, 4, 8 seconds
                        print("🔄 Retrying cloud sync in \(delay) seconds...")
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                            attemptSync()
                        }
                    } else {
                        self.endBackgroundTask(syncTask)
                    }
                }
            }
        }
        
        // Start sync process
        attemptSync()
    }
    
    private func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        
        // Must be on main thread
        if Thread.isMainThread {
            taskID = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.endBackgroundTask(taskID)
            }
        } else {
            DispatchQueue.main.sync {
                taskID = UIApplication.shared.beginBackgroundTask { [weak self] in
                    self?.endBackgroundTask(taskID)
                }
            }
        }
        
        return taskID
    }
    
    private func endBackgroundTask(_ taskID: UIBackgroundTaskIdentifier? = nil) {
        if let taskID = taskID, taskID != .invalid {
            if Thread.isMainThread {
                UIApplication.shared.endBackgroundTask(taskID)
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.endBackgroundTask(taskID)
                }
            }
        }
    }
    
    private func endProcessingBgTask(_ taskID: UIBackgroundTaskIdentifier? = nil) {
        endBackgroundTask(taskID)
    }
    
    private func endCloudSyncTask(_ taskID: UIBackgroundTaskIdentifier? = nil) {
        endBackgroundTask(taskID)
    }
}