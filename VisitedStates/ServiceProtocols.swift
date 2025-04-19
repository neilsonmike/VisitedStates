import Foundation
import CoreLocation
import Combine
import SwiftUI
import MapKit


// MARK: - Location Service Protocol

protocol LocationServiceProtocol: AnyObject {
    /// Current location reported by the service
    var currentLocation: CurrentValueSubject<CLLocation?, Never> { get }
    
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
}

// MARK: - Mock versions for testing

class MockLocationService: LocationServiceProtocol {
    var currentLocation = CurrentValueSubject<CLLocation?, Never>(nil)
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
        currentLocation.send(CLLocation(latitude: randomCoordinate.latitude, longitude: randomCoordinate.longitude))
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
        settings.addVisitedState(randomState)
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
}

class MockSettingsService: SettingsServiceProtocol {
    var visitedStates = CurrentValueSubject<[String], Never>([])
    var stateFillColor = CurrentValueSubject<Color, Never>(.red)
    var stateStrokeColor = CurrentValueSubject<Color, Never>(.white)
    var backgroundColor = CurrentValueSubject<Color, Never>(.white)
    var notificationsEnabled = CurrentValueSubject<Bool, Never>(true)
    var speedThreshold = CurrentValueSubject<Double, Never>(44.7)
    var altitudeThreshold = CurrentValueSubject<Double, Never>(3048)
    var lastVisitedState = CurrentValueSubject<String?, Never>(nil)
    
    func addVisitedState(_ state: String) {
        var states = visitedStates.value
        if !states.contains(state) {
            states.append(state)
            visitedStates.send(states)
            lastVisitedState.send(state)
        }
    }
    
    func removeVisitedState(_ state: String) {
        var states = visitedStates.value
        if let index = states.firstIndex(of: state) {
            states.remove(at: index)
            visitedStates.send(states)
        }
    }
    
    func setVisitedStates(_ states: [String]) {
        visitedStates.send(states)
    }
    
    func hasVisitedState(_ state: String) -> Bool {
        return visitedStates.value.contains(state)
    }
    
    func restoreDefaults() {
        stateFillColor.send(.red)
        stateStrokeColor.send(.white)
        backgroundColor.send(.white)
        notificationsEnabled.send(true)
        speedThreshold.send(44.7)
        altitudeThreshold.send(3048)
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
}
