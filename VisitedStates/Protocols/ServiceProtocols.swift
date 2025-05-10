import Foundation
import CoreLocation
import Combine
import SwiftUI
import MapKit


// MARK: - Location Service Protocol

protocol LocationServiceProtocol: AnyObject {
    /// Current location reported by the service
    var currentLocation: CurrentValueSubject<CLLocation?, Never> { get }
    
    /// Raw location updates including those filtered out by thresholds
    var rawLocationUpdates: CurrentValueSubject<CLLocation?, Never> { get }
    
    /// Current authorization status
    var authorizationStatus: CurrentValueSubject<CLAuthorizationStatus, Never> { get }
    
    /// Start location updates
    func startLocationUpdates()
    
    /// Stop location updates
    func stopLocationUpdates()
    
    /// Request "When In Use" authorization
    func requestWhenInUseAuthorization()
    
    /// Check if location services are enabled
    var isLocationServicesEnabled: Bool { get }
}

// MARK: - State Detection Service Protocol

protocol StateDetectionServiceProtocol: AnyObject {
    /// Process a new location to detect if the user has entered a new state
    func processLocation(_ location: CLLocation)
    
    /// Current state based on location
    var currentDetectedState: CurrentValueSubject<String?, Never> { get }
    
    /// Start state detection (typically calls locationService.startLocationUpdates)
    func startStateDetection()
    
    /// Stop state detection
    func stopStateDetection()
}

// MARK: - Cloud Sync Service Protocol

protocol CloudSyncServiceProtocol: AnyObject {
    /// Sync local states to CloudKit
    func syncToCloud(states: [String], completion: ((Result<Void, Error>) -> Void)?)
    
    /// Fetch states from CloudKit
    func fetchFromCloud(completion: @escaping (Result<[String], Error>) -> Void)
    
    /// Sync user settings to CloudKit
    func syncSettingsToCloud(completion: ((Result<Void, Error>) -> Void)?)
    
    /// Fetch user settings from CloudKit
    func fetchSettingsFromCloud(completion: ((Result<Void, Error>) -> Void)?)
    
    /// Current sync status
    var syncStatus: CurrentValueSubject<SyncStatus, Never> { get }
}

enum SyncStatus {
    case idle
    case syncing
    case succeeded
    case failed(Error)
}

// MARK: - Settings Service Protocol

protocol SettingsServiceProtocol: AnyObject {
    /// States the user has visited
    var visitedStates: CurrentValueSubject<[String], Never> { get }
    
    /// State appearance settings
    var stateFillColor: CurrentValueSubject<Color, Never> { get }
    var stateStrokeColor: CurrentValueSubject<Color, Never> { get }
    var backgroundColor: CurrentValueSubject<Color, Never> { get }
    
    /// User preferences
    var notificationsEnabled: CurrentValueSubject<Bool, Never> { get }
    var notifyOnlyNewStates: CurrentValueSubject<Bool, Never> { get }
    var speedThreshold: CurrentValueSubject<Double, Never> { get }
    var altitudeThreshold: CurrentValueSubject<Double, Never> { get }
    
    /// Add a visited state
    func addVisitedState(_ state: String)
    
    /// Remove a visited state
    func removeVisitedState(_ state: String)
    
    /// Set visited states
    func setVisitedStates(_ states: [String])
    
    /// Check if a state has been visited
    func hasVisitedState(_ state: String) -> Bool
    
    /// Restore default settings
    func restoreDefaults()
    
    /// Last visited state
    var lastVisitedState: CurrentValueSubject<String?, Never> { get }
    
    // Enhanced methods for badge and stats system
    
    /// Add a state via GPS detection (different from manual editing)
    func addStateViaGPS(_ state: String)
    
    /// Check if a state was ever visited via GPS, regardless of current status
    func wasStateEverVisitedViaGPS(_ state: String) -> Bool
    
    /// Get all states that were ever GPS verified
    func getAllGPSVerifiedStates() -> [VisitedState]
    
    /// Get only active GPS verified states
    func getActiveGPSVerifiedStates() -> [VisitedState]
    
    /// Get all earned badges
    func getEarnedBadges() -> [Badge]
}

// MARK: - Boundary Service Protocol

protocol StateBoundaryServiceProtocol: AnyObject {
    /// State polygons for rendering
    var statePolygons: [String: [MKPolygon]] { get }
    
    /// Determine which state a coordinate is in
    func stateName(for coordinate: CLLocationCoordinate2D) -> String?
    
    /// Get state borders for proximity checks
    func getStateBorders() -> [StateBorder]

    /// Load state boundary data
    func loadBoundaryData()
}

// MARK: - Notification Service Protocol

protocol NotificationServiceProtocol: AnyObject {
    /// Request notification permissions
    func requestNotificationPermissions()
    
    /// Schedule a notification for a newly visited state
    func scheduleStateEntryNotification(for state: String)
    
    /// Handle newly detected state
    func handleDetectedState(_ state: String)
    
    /// Check if notifications are authorized
    var isNotificationsAuthorized: CurrentValueSubject<Bool, Never> { get }
    
    /// Notify the service that cloud sync has completed
    func cloudSyncDidComplete()
}

// MARK: - Mock versions for testing

class MockLocationService: LocationServiceProtocol {
    var currentLocation = CurrentValueSubject<CLLocation?, Never>(nil)
    var rawLocationUpdates = CurrentValueSubject<CLLocation?, Never>(nil) // Added new property
    var authorizationStatus = CurrentValueSubject<CLAuthorizationStatus, Never>(.notDetermined)
    var isLocationServicesEnabled: Bool = true
    
    
    private let settings: SettingsServiceProtocol
    private let boundaryService: StateBoundaryServiceProtocol
    
    init(settings: SettingsServiceProtocol, boundaryService: StateBoundaryServiceProtocol) {
        self.settings = settings
        self.boundaryService = boundaryService
    }
    
    func startLocationUpdates() {
        // Simulate a location in a random state
        let randomCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let location = CLLocation(latitude: randomCoordinate.latitude, longitude: randomCoordinate.longitude)
        currentLocation.send(location)
        rawLocationUpdates.send(location) // Also send to the raw updates
    }
    
    func stopLocationUpdates() {
        // No-op in mock
    }
    
    // Change this method from requestAlwaysAuthorization to requestWhenInUseAuthorization
    func requestWhenInUseAuthorization() {
        authorizationStatus.send(.authorizedWhenInUse)
    }
}

class MockStateDetectionService: StateDetectionServiceProtocol {
    var currentDetectedState = CurrentValueSubject<String?, Never>(nil)
    
    private let locationService: LocationServiceProtocol
    private let boundaryService: StateBoundaryServiceProtocol
    private let settings: SettingsServiceProtocol
    private let cloudSync: CloudSyncServiceProtocol
    private let notificationService: NotificationServiceProtocol
    
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
    }
    
    func processLocation(_ location: CLLocation) {
        // Mock implementation - cycle through a few states
        let states = ["California", "Nevada", "Oregon"]
        let randomState = states.randomElement()!
        currentDetectedState.send(randomState)
        // Use GPS method instead of standard
        settings.addStateViaGPS(randomState)
        notificationService.handleDetectedState(randomState)
    }
    
    func startStateDetection() {
        locationService.startLocationUpdates()
    }
    
    func stopStateDetection() {
        locationService.stopLocationUpdates()
    }
}

class MockStateBoundaryService: StateBoundaryServiceProtocol {
    var statePolygons: [String: [MKPolygon]] = [:]
    
    func stateName(for coordinate: CLLocationCoordinate2D) -> String? {
        // Mock implementation
        if coordinate.latitude > 40 {
            return "Washington"
        } else if coordinate.latitude > 37 {
            return "Oregon"
        } else {
            return "California"
        }
    }
    
    func getStateBorders() -> [StateBorder] {
        // Mock implementation - return empty array
        return []
    }
    
    func loadBoundaryData() {
        // Mock implementation - would normally load GeoJSON data
        print("Mock boundary data loaded")
    }
}

class MockCloudSyncService: CloudSyncServiceProtocol {
    var syncStatus = CurrentValueSubject<SyncStatus, Never>(.idle)
    private let settings: SettingsServiceProtocol
    
    init(settings: SettingsServiceProtocol) {
        self.settings = settings
    }
    
    func syncToCloud(states: [String], completion: ((Result<Void, Error>) -> Void)?) {
        syncStatus.send(.syncing)
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncStatus.send(.succeeded)
            completion?(.success(()))
        }
    }
    
    func fetchFromCloud(completion: @escaping (Result<[String], Error>) -> Void) {
        syncStatus.send(.syncing)
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncStatus.send(.succeeded)
            completion(.success(["California", "Nevada"]))
        }
    }
    
    func syncSettingsToCloud(completion: ((Result<Void, Error>) -> Void)?) {
        syncStatus.send(.syncing)
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncStatus.send(.succeeded)
            print("📤 [MOCK] Synced settings to cloud")
            completion?(.success(()))
        }
    }
    
    func fetchSettingsFromCloud(completion: ((Result<Void, Error>) -> Void)?) {
        syncStatus.send(.syncing)
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncStatus.send(.succeeded)
            print("📥 [MOCK] Fetched settings from cloud")
            completion?(.success(()))
        }
    }
}

class MockSettingsService: SettingsServiceProtocol {
    var visitedStates = CurrentValueSubject<[String], Never>([])
    var stateFillColor = CurrentValueSubject<Color, Never>(.red)
    var stateStrokeColor = CurrentValueSubject<Color, Never>(.white)
    var backgroundColor = CurrentValueSubject<Color, Never>(.white)
    var notificationsEnabled = CurrentValueSubject<Bool, Never>(true)
    var speedThreshold = CurrentValueSubject<Double, Never>(100.0) // Updated to 100 mph
    var altitudeThreshold = CurrentValueSubject<Double, Never>(10000.0) // Updated to 10,000 feet
    var lastVisitedState = CurrentValueSubject<String?, Never>(nil)
    var notifyOnlyNewStates = CurrentValueSubject<Bool, Never>(false)
    
    private var visitedStateModels: [VisitedState] = []
    private var badges: [Badge] = []
    
    func addVisitedState(_ state: String) {
        addStateWithDetails(state, viaGPS: false)
    }
    
    func removeVisitedState(_ state: String) {
        if let index = visitedStateModels.firstIndex(where: { $0.stateName == state }) {
            var updatedState = visitedStateModels[index]
            updatedState.isActive = false
            visitedStateModels[index] = updatedState
            updateVisitedStatesArray()
        } else {
            var states = visitedStates.value
            if let index = states.firstIndex(of: state) {
                states.remove(at: index)
                visitedStates.send(states)
            }
        }
    }
    
    func setVisitedStates(_ states: [String]) {
        let currentActiveStates = visitedStateModels.filter({ $0.isActive }).map({ $0.stateName })
        let statesToAdd = states.filter { !currentActiveStates.contains($0) }
        let statesToRemove = currentActiveStates.filter { !states.contains($0) }
        
        for state in statesToAdd {
            addStateWithDetails(state, viaGPS: false)
        }
        
        for state in statesToRemove {
            removeVisitedState(state)
        }
        
        updateVisitedStatesArray()
    }
    
    func hasVisitedState(_ state: String) -> Bool {
        return visitedStateModels.contains(where: { $0.stateName == state && $0.isActive }) ||
               visitedStates.value.contains(state)
    }
    
    func restoreDefaults() {
        stateFillColor.send(.red)
        stateStrokeColor.send(.white)
        backgroundColor.send(.white)
        notificationsEnabled.send(true)
        notifyOnlyNewStates.send(false)
        speedThreshold.send(100.0) // Updated to 100 mph
        altitudeThreshold.send(10000.0) // Updated to 10,000 feet
    }
    
    func addStateViaGPS(_ state: String) {
        addStateWithDetails(state, viaGPS: true)
    }
    
    func wasStateEverVisitedViaGPS(_ state: String) -> Bool {
        return visitedStateModels.contains(where: { $0.stateName == state && $0.wasEverVisited })
    }
    
    func getAllGPSVerifiedStates() -> [VisitedState] {
        return visitedStateModels.filter { $0.wasEverVisited }
    }
    
    func getActiveGPSVerifiedStates() -> [VisitedState] {
        return visitedStateModels.filter { $0.wasEverVisited && $0.isActive }
    }
    
    func getEarnedBadges() -> [Badge] {
        return badges.filter { $0.isEarned }
    }
    
    // MARK: - Private methods
    
    private func addStateWithDetails(_ state: String, viaGPS: Bool) {
        if let index = visitedStateModels.firstIndex(where: { $0.stateName == state }) {
            var updatedState = visitedStateModels[index]
            
            if viaGPS {
                updatedState.visited = true
                updatedState.wasEverVisited = true
                
                if updatedState.firstVisitedDate == nil {
                    updatedState.firstVisitedDate = Date()
                }
                updatedState.lastVisitedDate = Date()
            } else {
                if updatedState.wasEverVisited {
                    updatedState.visited = updatedState.wasEverVisited
                }
                updatedState.edited = true
            }
            
            updatedState.isActive = true
            visitedStateModels[index] = updatedState
        } else {
            let newState = VisitedState(
                stateName: state,
                visited: viaGPS,
                edited: !viaGPS,
                firstVisitedDate: viaGPS ? Date() : nil,
                lastVisitedDate: viaGPS ? Date() : nil,
                isActive: true,
                wasEverVisited: viaGPS
            )
            visitedStateModels.append(newState)
        }
        
        updateVisitedStatesArray()
    }
    
    private func updateVisitedStatesArray() {
        let activeStates = visitedStateModels.filter { $0.isActive }.map { $0.stateName }
        visitedStates.send(activeStates)
    }
}

class MockNotificationService: NotificationServiceProtocol {
    var isNotificationsAuthorized = CurrentValueSubject<Bool, Never>(false)
    private let settings: SettingsServiceProtocol
    
    init(settings: SettingsServiceProtocol) {
        self.settings = settings
    }
    
    func requestNotificationPermissions() {
        isNotificationsAuthorized.send(true)
    }
    
    func scheduleStateEntryNotification(for state: String) {
        print("Mock notification scheduled for \(state)")
    }
    
    func handleDetectedState(_ state: String) {
        if settings.notificationsEnabled.value {
            scheduleStateEntryNotification(for: state)
        }
    }
    
    func cloudSyncDidComplete() {
        print("Mock notification service received cloud sync completion")
    }
}
