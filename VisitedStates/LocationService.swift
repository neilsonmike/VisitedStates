import Foundation
import CoreLocation
import Combine
import UIKit

class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    // MARK: - Properties
    
    var currentLocation = CurrentValueSubject<CLLocation?, Never>(nil)
    var authorizationStatus = CurrentValueSubject<CLAuthorizationStatus, Never>(.notDetermined)
    private var locationManager: CLLocationManager
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Dependencies
    private let settings: SettingsServiceProtocol
    private let boundaryService: StateBoundaryServiceProtocol
    
    // Location update configuration
    private let highAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    private let mediumAccuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer
    private let lowAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
    
    private let closeToStateBorderDistance: CLLocationDistance = 15000 // 15km
    private let standardDistanceFilter: CLLocationDistance = 500 // 500m in foreground
    private let backgroundDistanceFilter: CLLocationDistance = 2000 // 2km in background
    private let farDistanceFilter: CLLocationDistance = 5000 // 5km when far from borders
    
    // State for adaptive monitoring
    private var lastKnownState: String?
    private var isCloseToStateBorder: Bool = false
    private var lastStateUpdateTime: Date?
    private var currentMonitoringRegions: [CLCircularRegion] = []
    
    // Battery monitoring
    private var batteryLevel: Float = 1.0
    private var batteryIsLow: Bool = false
    private let lowBatteryThreshold: Float = 0.2
    
    // Background restart timer
    private var backgroundRestartTimer: Timer?
    private let backgroundRestartInterval: TimeInterval = 1800 // 30 minutes (increased from 15)
    
    // Region monitoring
    private let maxMonitoredRegions = 18 // iOS limit is 20, keep 2 slots free
    
    // MARK: - Initialization
    
    init(settings: SettingsServiceProtocol, boundaryService: StateBoundaryServiceProtocol) {
        self.settings = settings
        self.boundaryService = boundaryService
        
        locationManager = CLLocationManager()
        super.init()
        
        locationManager.delegate = self
        configureLocationManager()
        
        // Set initial authorization status
        authorizationStatus.send(locationManager.authorizationStatus)
        
        // Register for app lifecycle notifications
        setupNotificationObservers()
        
        // Setup battery monitoring
        setupBatteryMonitoring()
        
        print("🚀 LocationService initialized")
    }
    
    deinit {
        stopBackgroundRestartTimer()
        removeNotificationObservers()
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: nil)
    }
    
    // MARK: - LocationServiceProtocol
    
    var isLocationServicesEnabled: Bool {
        return CLLocationManager.locationServicesEnabled()
    }
    
    func startLocationUpdates() {
        guard isLocationServicesEnabled else {
            print("🔍 Location services are disabled")
            return
        }
        
        print("🚀 Starting location updates...")
        
        switch authorizationStatus.value {
        case .authorizedWhenInUse, .authorizedAlways:
            // Set up initial accuracy based on context
            applyLocationAccuracyStrategy()
            locationManager.startUpdatingLocation()
            print("🔍 Started location updates with accuracy: \(locationManager.desiredAccuracy)")
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("🔍 Location services are restricted or denied")
        @unknown default:
            print("🔍 Unknown location authorization status")
        }
    }
    
    func stopLocationUpdates() {
        stopBackgroundRestartTimer()
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        removeAllMonitoredRegions()
        print("🔍 Stopped all location updates")
    }
    
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }
    
    // MARK: - Private methods
    
    private func configureLocationManager() {
        // Start with medium accuracy
        locationManager.desiredAccuracy = mediumAccuracy
        locationManager.distanceFilter = standardDistanceFilter
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .other
        
        // Only set allowsBackgroundLocationUpdates if background modes are enabled
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
               modes.contains("location") {
                locationManager.allowsBackgroundLocationUpdates = true
                locationManager.showsBackgroundLocationIndicator = true
                print("✅ Background location updates enabled")
            } else {
                print("⚠️ No location background mode in Info.plist")
            }
        } else {
            print("⚠️ No UIBackgroundModes in Info.plist")
        }
    }
    
    private func setupNotificationObservers() {
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
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupBatteryMonitoring() {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Get initial battery state
        updateBatteryState()
        
        // Subscribe to battery notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelDidChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateDidChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func batteryLevelDidChange(_ notification: Notification) {
        updateBatteryState()
    }
    
    @objc private func batteryStateDidChange(_ notification: Notification) {
        updateBatteryState()
    }
    
    private func updateBatteryState() {
        batteryLevel = UIDevice.current.batteryLevel
        
        // Check if battery is low
        let previousBatteryState = batteryIsLow
        batteryIsLow = batteryLevel <= lowBatteryThreshold && batteryLevel > 0
        
        // If battery state changed, update location accuracy strategy
        if previousBatteryState != batteryIsLow {
            print("🔋 Battery state changed. Level: \(batteryLevel * 100)%, Low: \(batteryIsLow)")
            applyLocationAccuracyStrategy()
        }
    }
    
    @objc private func appDidEnterBackground() {
        print("🔍 App entered background")
        
        // Cancel any existing background task
        endBackgroundTask()
        
        // Start a new background task for the transition
        backgroundTask = beginBackgroundTask()
        
        // Add a delay to ensure any pending updates are processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Transition to background mode
            self.transitionToBackgroundMode()
            
            // Start the background restart timer
            self.startBackgroundRestartTimer()
            
            // End this background task after allowing time for transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.endBackgroundTask()
            }
        }
    }
    
    @objc private func appDidBecomeActive() {
        print("🔍 App became active")
        
        // End any background task
        endBackgroundTask()
        
        // Stop the background restart timer
        stopBackgroundRestartTimer()
        
        // Transition to foreground mode
        transitionToForegroundMode()
    }
    
    @objc private func appWillTerminate() {
        print("🔍 App will terminate")
        
        // Save state and ensure background task is ended
        endBackgroundTask()
        stopBackgroundRestartTimer()
    }
    
    private func transitionToBackgroundMode() {
        // In background, use a mix of approaches for reliable detection
        
        // 1. Stop continuous updates to save battery
        locationManager.stopUpdatingLocation()
        
        // 2. Clean up any existing monitoring
        removeAllMonitoredRegions()
        
        // 3. Start significant location changes for baseline monitoring
        locationManager.startMonitoringSignificantLocationChanges()
        print("🔍 Started significant location change monitoring")
        
        // 4. Set up state border monitoring with geofencing
        setupImprovedStateTransitionMonitoring()
        
        print("🔍 Switched to background mode: significant location changes + geofencing")
    }
    
    private func transitionToForegroundMode() {
        // Stop background-specific updates
        locationManager.stopMonitoringSignificantLocationChanges()
        
        // Remove any geofencing regions
        removeAllMonitoredRegions()
        
        // Apply adaptive accuracy based on current context
        applyLocationAccuracyStrategy()
        
        // Start standard updates
        locationManager.startUpdatingLocation()
        
        print("🔍 Switched to foreground mode with adaptive accuracy")
    }
    
    private func startBackgroundRestartTimer() {
        // Stop any existing timer
        stopBackgroundRestartTimer()
        
        // Create a new timer that periodically restarts location services
        // This helps prevent iOS from aggressively throttling location in background
        backgroundRestartTimer = Timer.scheduledTimer(
            timeInterval: backgroundRestartInterval,
            target: self,
            selector: #selector(backgroundRestartTimerFired),
            userInfo: nil,
            repeats: true
        )
        
        print("🕒 Started background restart timer: interval \(backgroundRestartInterval)s")
    }
    
    private func stopBackgroundRestartTimer() {
        backgroundRestartTimer?.invalidate()
        backgroundRestartTimer = nil
    }
    
    @objc private func backgroundRestartTimerFired() {
        print("🕒 Background restart timer fired")
        
        // Create a background task for this restart
        let taskID = beginBackgroundTask()
        
        // Restart significant location changes monitoring
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.startMonitoringSignificantLocationChanges()
        
        // Request a one-time location update
        locationManager.requestLocation()
        
        // End the background task after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.endBackgroundTask(taskID)
        }
    }
    
    private func endBackgroundTask(_ taskID: UIBackgroundTaskIdentifier? = nil) {
        let taskToEnd = taskID ?? backgroundTask
        
        if taskToEnd != .invalid {
            UIApplication.shared.endBackgroundTask(taskToEnd)
            if taskToEnd == backgroundTask {
                backgroundTask = .invalid
            }
        }
    }
    
    private func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        return UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func applyLocationAccuracyStrategy() {
        // Base strategy on several factors:
        // 1. Proximity to state borders
        // 2. Battery level
        // 3. App state (foreground/background)
        
        var newAccuracy: CLLocationAccuracy
        var newDistanceFilter: CLLocationDistance
        
        // Determine base accuracy by border proximity
        if isCloseToStateBorder {
            newAccuracy = highAccuracy
            newDistanceFilter = standardDistanceFilter
            print("🔍 Close to border - using higher accuracy")
        } else {
            newAccuracy = mediumAccuracy
            newDistanceFilter = farDistanceFilter
            print("🔍 Far from border - using lower accuracy")
        }
        
        // Adjust for battery level
        if batteryIsLow {
            // Reduce accuracy when battery is low
            if newAccuracy == highAccuracy {
                newAccuracy = mediumAccuracy
            } else if newAccuracy == mediumAccuracy {
                newAccuracy = lowAccuracy
            }
            
            // Increase distance filter to reduce updates
            newDistanceFilter *= 2
            print("🔋 Low battery - reducing accuracy")
        }
        
        // Adjust for background state if needed
        if UIApplication.shared.applicationState == .background {
            // Further reduce accuracy in background
            if newAccuracy == highAccuracy {
                newAccuracy = mediumAccuracy
            }
            newDistanceFilter = max(newDistanceFilter, backgroundDistanceFilter)
            print("🔍 Background mode - adjusting accuracy settings")
        }
        
        // Apply the new settings
        if locationManager.desiredAccuracy != newAccuracy {
            locationManager.desiredAccuracy = newAccuracy
            print("🔍 Updated location accuracy to: \(newAccuracy)")
        }
        
        if locationManager.distanceFilter != newDistanceFilter {
            locationManager.distanceFilter = newDistanceFilter
            print("🔍 Updated distance filter to: \(newDistanceFilter)m")
        }
    }
    
    private func checkProximityToStateBorders(_ location: CLLocation) {
        // Get current state
        let currentState = boundaryService.stateName(for: location.coordinate)
        
        // Check if this is a state transition
        let stateChanged = currentState != lastKnownState && currentState != nil
        if stateChanged {
            // If we changed states, we're definitely near a border
            isCloseToStateBorder = true
            lastKnownState = currentState
            lastStateUpdateTime = Date()
            print("🔍 State transition detected: now in \(currentState ?? "unknown state")")
            
            // Set up border monitoring
            setupImprovedStateTransitionMonitoring()
        } else {
            // If no state change, calculate actual proximity to borders
            findNearbyStateBorders(location)
        }
        
        // If state hasn't changed in a while and we're not near borders,
        // we're likely in the middle of a state
        if let lastUpdate = lastStateUpdateTime,
           Date().timeIntervalSince(lastUpdate) > 300 && // 5 minutes
           !isCloseToStateBorder {
            // Reduce accuracy since we're likely not near borders
            applyLocationAccuracyStrategy()
        }
    }
    
    private func findNearbyStateBorders(_ location: CLLocation) {
        // Get the current state
        guard let currentState = boundaryService.stateName(for: location.coordinate) else {
            return
        }
        
        // Check points in cardinal directions ~10km away
        let distanceInDegrees = 0.1 // Approximately 10km
        let testPoints = [
            CLLocationCoordinate2D(latitude: location.coordinate.latitude + distanceInDegrees, longitude: location.coordinate.longitude), // North
            CLLocationCoordinate2D(latitude: location.coordinate.latitude - distanceInDegrees, longitude: location.coordinate.longitude), // South
            CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude + distanceInDegrees), // East
            CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude - distanceInDegrees)  // West
        ]
        
        // Check if any test point is in a different state
        var nearBorder = false
        var borderDirection: CLLocationCoordinate2D?
        var nearbyStates = Set<String>()
        
        for point in testPoints {
            if let pointState = boundaryService.stateName(for: point), pointState != currentState {
                nearBorder = true
                borderDirection = point
                nearbyStates.insert(pointState)
            }
        }
        
        // Update border proximity state
        let wasNearBorder = isCloseToStateBorder
        isCloseToStateBorder = nearBorder
        
        // If border proximity changed, update strategy
        if wasNearBorder != isCloseToStateBorder {
            print("🔍 Border proximity changed: \(isCloseToStateBorder ? "near border" : "away from borders")")
            
            applyLocationAccuracyStrategy()
            
            // If we're near a border, set up geofencing
            if isCloseToStateBorder, let direction = borderDirection {
                setupGeofenceForBorder(current: location.coordinate, direction: direction)
            } else {
                // If we're no longer near a border, remove monitoring
                removeAllMonitoredRegions()
            }
        }
    }
    
    private func setupGeofenceForBorder(current: CLLocationCoordinate2D, direction: CLLocationCoordinate2D) {
        // Only proceed if region monitoring is available
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return
        }
        
        // Remove existing regions
        removeAllMonitoredRegions()
        
        // Calculate midpoint between current location and border direction
        let midLat = (current.latitude + direction.latitude) / 2
        let midLon = (current.longitude + direction.longitude) / 2
        let midpoint = CLLocationCoordinate2D(latitude: midLat, longitude: midLon)
        
        // Create a circular region that covers the likely border area
        let borderRegion = CLCircularRegion(
            center: midpoint,
            radius: 5000, // 5km radius
            identifier: "StateBorder_\(UUID().uuidString.prefix(8))"
        )
        
        borderRegion.notifyOnEntry = true
        borderRegion.notifyOnExit = true
        
        // Start monitoring the region
        safelyMonitorRegion(borderRegion)
        
        print("🔍 Set up geofence for potential state border crossing")
    }
    
    private func setupImprovedStateTransitionMonitoring() {
        // Clear all existing regions first
        removeAllMonitoredRegions()
        
        // Add a delay to ensure cleanup is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            // Get current location if available
            guard let location = self.currentLocation.value else {
                print("⚠️ No location available for state monitoring setup")
                return
            }
            
            // Get current state
            guard let currentState = self.boundaryService.stateName(for: location.coordinate) else {
                print("⚠️ Could not determine current state for monitoring setup")
                return
            }
            
            print("🔍 Setting up improved state monitoring for \(currentState)")
            
            // Get state borders from boundary service
            let allBorders = self.boundaryService.getStateBorders()
            
            // Find borders for states that are not the current state
            let potentialBorders = allBorders.filter { $0.stateName != currentState }
            
            // Find closest border points (up to 3) within reasonable distance
            var closestBorders: [(border: StateBorder, distance: CLLocationDistance)] = []
            
            for border in potentialBorders {
                let distance = border.distanceTo(location.coordinate)
                if distance < 50000 { // 50km
                    closestBorders.append((border, distance))
                }
            }
            
            // Sort by distance and take closest 3
            closestBorders.sort { $0.distance < $1.distance }
            let monitorBorders = closestBorders.prefix(3)
            
            if monitorBorders.isEmpty {
                print("🔍 No nearby state borders found, monitoring current state exit only")
                
                // If no borders nearby, monitor current state with a larger region
                let stateRegion = CLCircularRegion(
                    center: location.coordinate,
                    radius: 10000, // 10km radius
                    identifier: "CurrentState_\(currentState)_\(UUID().uuidString.prefix(8))"
                )
                stateRegion.notifyOnExit = true // Only care when leaving current state
                self.safelyMonitorRegion(stateRegion)
            } else {
                // Add monitoring regions for each nearby border
                for (index, borderInfo) in monitorBorders.enumerated() {
                    let border = borderInfo.border
                    
                    // Get a representative point from the border
                    let midIndex = min(border.coordinates.count / 2, border.coordinates.count - 1)
                    let borderPoint = border.coordinates[midIndex]
                    
                    // Create region centered on border point
                    let region = CLCircularRegion(
                        center: borderPoint,
                        radius: 3000, // 3km radius
                        identifier: "Border_\(border.stateName)_\(index)_\(UUID().uuidString.prefix(5))"
                    )
                    region.notifyOnEntry = true
                    region.notifyOnExit = true
                    
                    self.safelyMonitorRegion(region)
                    print("🔍 Added monitoring for border with \(border.stateName), distance: \(Int(borderInfo.distance))m")
                }
            }
            
            // Request temporary precision location when near borders (iOS 14+)
            if #available(iOS 14.0, *) {
                self.locationManager.requestTemporaryFullAccuracyAuthorization(
                    withPurposeKey: "StateTransitionPurposeKey"
                ) { error in
                    if let error = error {
                        print("⚠️ Failed to get temporary precise location: \(error.localizedDescription)")
                    } else {
                        print("✅ Received temporary precise location permission")
                    }
                }
            }
        }
    }
    
    private func safelyMonitorRegion(_ region: CLCircularRegion) {
        // Check if we're already monitoring too many regions
        if locationManager.monitoredRegions.count >= maxMonitoredRegions {
            print("⚠️ Already monitoring max regions (\(maxMonitoredRegions)), removing oldest")
            if let oldestRegion = currentMonitoringRegions.first {
                locationManager.stopMonitoring(for: oldestRegion)
                currentMonitoringRegions.removeFirst()
            }
        }
        
        // Start monitoring with verification
        locationManager.startMonitoring(for: region)
        currentMonitoringRegions.append(region)
        print("🔍 Added monitoring region: \(region.identifier)")
    }
    
    private func removeAllMonitoredRegions() {
        // Remove all regions we've set up
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        currentMonitoringRegions.removeAll()
        print("🔍 Removed all monitored regions")
    }
    
    private func isValidLocation(_ location: CLLocation) -> Bool {
        // Convert values to user-friendly units for logging
        let speedMph = location.speed * 2.23694 // m/s to mph
        let altitudeFeet = location.altitude * 3.28084 // meters to feet
        
        // Get threshold values from settings
        let speedThreshold = settings.speedThreshold.value
        let altitudeThreshold = settings.altitudeThreshold.value
        
        // Check altitude threshold - this is still valid to check
        if altitudeFeet > altitudeThreshold {
            print("Ignoring location: altitude = \(altitudeFeet) ft exceeds threshold of \(altitudeThreshold) ft")
            return false
        }
        
        // Check positive speed threshold - but allow negative speeds
        // This is important for GPX testing
        if location.speed > 0 && speedMph > speedThreshold {
            print("Ignoring location: speed = \(speedMph) mph exceeds threshold of \(speedThreshold) mph")
            return false
        }
        
        // Check horizontal accuracy - discard very inaccurate readings
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 1000 {
            print("Ignoring location: horizontalAccuracy = \(location.horizontalAccuracy)m is invalid")
            return false
        }
        
        // If we got here, location is valid
        return true
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus.send(manager.authorizationStatus)
        
        // Start updates if we have authorization
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            startLocationUpdates()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Start a new background task for this specific location update
        let taskID = beginBackgroundTask()
        
        // Filter out invalid locations
        if !isValidLocation(location) {
            endBackgroundTask(taskID)
            return
        }
        
        // Update the current location
        currentLocation.send(location)
        
        // Check if we're near state borders and adjust strategy accordingly
        checkProximityToStateBorders(location)
        
        // End the background task
        endBackgroundTask(taskID)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ Location Manager error: \(error.localizedDescription)")
        
        // Attempt to recover based on the error
        if let error = error as? CLError {
            switch error.code {
            case .denied:
                // User denied authorization, stop updates
                stopLocationUpdates()
            case .network:
                // Network error, retry after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.startLocationUpdates()
                }
            case .locationUnknown:
                // Temporary inability to get location, just wait for next update
                break
            default:
                // For other errors, try resetting the location manager if persistent
                if error.code.rawValue >= 2 && error.code.rawValue <= 4 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        self?.resetLocationManager()
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("🏁 Entered region: \(region.identifier)")
        
        // For state border regions, increase accuracy and force an update
        if region.identifier.starts(with: "StateBorder_") ||
           region.identifier.starts(with: "Border_") {
            isCloseToStateBorder = true
            applyLocationAccuracyStrategy()
            
            // Force a location update to check for state changes
            manager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("🏁 Exited region: \(region.identifier)")
        
        // If we exit a state monitoring region, force a location update
        if region.identifier.starts(with: "StateBorder_") ||
           region.identifier.starts(with: "Border_") ||
           region.identifier.starts(with: "CurrentState_") {
            // Force an immediate location update to check for state changes
            manager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("⚠️ Region monitoring failed: \(error.localizedDescription)")
        
        // Try to recover from region monitoring failure
        if let region = region {
            // Stop monitoring the problematic region
            locationManager.stopMonitoring(for: region)
            
            // Remove from our tracking list
            if let index = currentMonitoringRegions.firstIndex(where: { $0.identifier == region.identifier }) {
                currentMonitoringRegions.remove(at: index)
            }
        }
    }
    
    private func resetLocationManager() {
        // Sometimes completely resetting the location manager can fix persistent errors
        print("🔄 Resetting location manager")
        
        // Stop all updates
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        removeAllMonitoredRegions()
        
        // Recreate and reconfigure
        locationManager = CLLocationManager()
        locationManager.delegate = self
        configureLocationManager()
        
        // Restart updates
        startLocationUpdates()
    }
}
