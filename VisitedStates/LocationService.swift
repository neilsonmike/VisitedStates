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
    private let standardAccuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer
    private let standardDistanceFilter: CLLocationDistance = 1000 // 1km
    
    // State for location monitoring
    private var lastKnownState: String?
    private var lastStateUpdateTime: Date?
    
    // Battery monitoring
    private var batteryLevel: Float = 1.0
    private var batteryIsLow: Bool = false
    private let lowBatteryThreshold: Float = 0.2
    
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
            if UIApplication.shared.applicationState == .active {
                locationManager.startUpdatingLocation()
                print("🔍 Started standard location updates")
            } else {
                locationManager.startMonitoringSignificantLocationChanges()
                print("🔍 Started significant location changes")
            }
        case .notDetermined:
            // FIXED: Do not directly request authorization
            // Use our thread-safe method instead
            requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("🔍 Location services are restricted or denied")
        @unknown default:
            print("🔍 Unknown location authorization status")
        }
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        print("🔍 Stopped all location updates")
    }
    
    func requestWhenInUseAuthorization() {
        // FIXED: Always use dispatch_async to avoid blocking main thread
        DispatchQueue.global().async { [weak self] in
            self?.locationManager.requestWhenInUseAuthorization()
        }
    }
    
    // MARK: - Private methods
    
    private func configureLocationManager() {
        // Configure for standard accuracy and distance
        locationManager.desiredAccuracy = standardAccuracy
        locationManager.distanceFilter = standardDistanceFilter
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .other
        
        // This tells iOS to restart your app for location updates after reboot
        locationManager.startMonitoringSignificantLocationChanges()
        
        print("🔧 Configured location manager with standard settings")
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
        
        // If battery state changed, adjust location updates
        if previousBatteryState != batteryIsLow {
            print("🔋 Battery state changed. Level: \(batteryLevel * 100)%, Low: \(batteryIsLow)")
            
            if batteryIsLow {
                // Reduce updates when battery is low
                locationManager.distanceFilter = standardDistanceFilter * 2
                print("🔋 Low battery - reducing location updates frequency")
            } else {
                // Normal updates when battery is fine
                locationManager.distanceFilter = standardDistanceFilter
            }
        }
    }
    
    @objc private func appDidEnterBackground() {
        print("🔍 App entered background")
        
        // Cancel any existing background task
        endBackgroundTask()
        
        // Start a new background task for the transition
        backgroundTask = beginBackgroundTask()
        
        // Transition to background mode
        locationManager.stopUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        print("🔍 Switched to significant location changes in background")
        
        // End background task after allowing time for transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    @objc private func appDidBecomeActive() {
        print("🔍 App became active")
        
        // End any background task
        endBackgroundTask()
        
        // Transition to foreground mode
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.startUpdatingLocation()
        
        print("🔍 Switched to standard location updates in foreground")
    }
    
    @objc private func appWillTerminate() {
        print("🔍 App will terminate")
        
        // Ensure background task is ended
        endBackgroundTask()
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
        
        // Make state detection from this location
        if let stateName = boundaryService.stateName(for: location.coordinate) {
            // Check if state has changed
            if stateName != lastKnownState {
                print("🗺️ State changed: \(lastKnownState ?? "none") -> \(stateName)")
                lastKnownState = stateName
                lastStateUpdateTime = Date()
            }
        }
        
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
    
    private func resetLocationManager() {
        // Sometimes completely resetting the location manager can fix persistent errors
        print("🔄 Resetting location manager")
        
        // Stop all updates
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        
        // Recreate and reconfigure
        locationManager = CLLocationManager()
        locationManager.delegate = self
        configureLocationManager()
        
        // Restart updates
        startLocationUpdates()
    }
}
