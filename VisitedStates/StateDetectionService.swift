import Foundation
import CoreLocation
import Combine
import UIKit

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
    
    // State detection parameters
    private var consecutiveFailedDetections = 0
    private let maxConsecutiveFailedDetections = 3
    private var lastLocationByState: [String: CLLocation] = [:]
    private var pendingAirportDetections: [String: Date] = [:]
    private var lastProcessedLocation: CLLocation?
    private var stateDetectionCache: [String: Date] = [:]
    private let stateCacheDuration: TimeInterval = 3600 * 24 // 24 hours
    private let minimumDistanceForNewDetection: CLLocationDistance = 50 // Reduced for testing
    
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
    }
    
    // MARK: - StateDetectionServiceProtocol
    
    func startStateDetection() {
        guard !isDetecting else { return }
        isDetecting = true
        locationService.startLocationUpdates()
        print("🗺️ Started state detection")
    }
    
    func stopStateDetection() {
        guard isDetecting else { return }
        isDetecting = false
        locationService.stopLocationUpdates()
        print("🗺️ Stopped state detection")
    }
    
    func processLocation(_ location: CLLocation) {
        print("🧩 Processing location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // Create a background task for this processing
        let bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endProcessingBgTask()
        }
        
        // Skip if this is a duplicate or very close to previously processed location
        // Uncomment for production - useful during testing to process all locations
        /*
        if let lastLocation = self.lastProcessedLocation,
           location.distance(from: lastLocation) < self.minimumDistanceForNewDetection {
            // Only process locations that are at least 50m apart to reduce processing load
            print("⏭️ Skipping location - too close to previous (\(location.distance(from: lastLocation))m)")
            endProcessingBgTask(bgTask)
            return
        }
        */
        
        // Update last processed location
        self.lastProcessedLocation = location
        
        // Detect the state for this location
        if let stateName = self.detectStateWithFallbacks(for: location) {
            print("🧩 Detected state: \(stateName)")
            
            // Update the current detected state (on main thread)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    // End the background task if self no longer exists
                    UIApplication.shared.endBackgroundTask(bgTask)
                    return
                }
                
                // Get current state before updating
                let previousState = self.currentDetectedState.value
                
                // Only send if the state has changed
                if previousState != stateName {
                    print("✨ NEW STATE DETECTED: \(stateName) (previous: \(previousState ?? "none"))")
                    self.currentDetectedState.send(stateName)
                    
                    // *** MOVED THIS SECTION UP - Only notify on state change ***
                    // Always notify about state detection when the state changes
                    self.notifyStateChange(stateName)
                }
                
                // Keep track of last known location in this state
                self.lastLocationByState[stateName] = location
                
                // Store detection time for caching
                self.stateDetectionCache[stateName] = Date()
                
                // Add to visited states if not already there
                if !self.settings.hasVisitedState(stateName) {
                    print("📝 Adding new state to visited list: \(stateName)")
                    self.settings.addVisitedState(stateName)
                    
                    // Sync with cloud
                    self.syncToCloud()
                } else {
                    print("📝 State already in visited list: \(stateName)")
                }
                
                // End the background task
                UIApplication.shared.endBackgroundTask(bgTask)
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
            endProcessingBgTask(bgTask)
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
                    if self?.isDetecting == true {
                        self?.locationService.startLocationUpdates()
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
            guard let self = self else { return }
            
            // Only update if state has changed
            if self.currentDetectedState.value != state {
                print("✨ NEW STATE DETECTED (fallback): \(state) (previous: \(self.currentDetectedState.value ?? "none"))")
                self.currentDetectedState.send(state)
                
                // Always notify about state detection if state changed
                self.notifyStateChange(state)
            }
            
            // Add to visited states if needed
            if !self.settings.hasVisitedState(state) {
                print("📝 Adding new state to visited list (fallback): \(state)")
                self.settings.addVisitedState(state)
                self.syncToCloud()
            } else {
                print("📝 State already in visited list: \(state)")
            }
        }
    }
    
    private func notifyStateChange(_ state: String) {
        // Always notify about state changes, even for previously visited states
        // This is the single control point for notifications
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("🗺️ Notifying about state entry: \(state)")
            self.notificationService.handleDetectedState(state)
        }
    }
    
    private func syncToCloud() {
        print("☁️ Syncing states to cloud...")
        
        // Create background task for cloud sync
        let syncTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endCloudSyncTask()
        }
        
        // Sync with cloud with retry logic
        var retryCount = 0
        let maxRetries = 3
        
        func attemptSync() {
            self.cloudSync.syncToCloud(states: self.settings.visitedStates.value) { [weak self] result in
                guard let self = self else {
                    UIApplication.shared.endBackgroundTask(syncTask)
                    return
                }
                
                switch result {
                case .success:
                    print("✅ Successfully synced states to cloud")
                    UIApplication.shared.endBackgroundTask(syncTask)
                    
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
                        UIApplication.shared.endBackgroundTask(syncTask)
                    }
                }
            }
        }
        
        // Start sync process
        attemptSync()
    }
    
    private func endProcessingBgTask(_ taskID: UIBackgroundTaskIdentifier? = nil) {
        if let taskID = taskID, taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }
    
    private func endCloudSyncTask(_ taskID: UIBackgroundTaskIdentifier? = nil) {
        if let taskID = taskID, taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }
}
