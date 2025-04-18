import Foundation
import SwiftUI

/// Central container for app dependencies
/// This allows for proper dependency injection rather than global singletons
class AppDependencies: ObservableObject {
    // Core services
    let locationService: LocationServiceProtocol
    let stateDetectionService: StateDetectionServiceProtocol
    let cloudSyncService: CloudSyncServiceProtocol
    let notificationService: NotificationServiceProtocol
    let settingsService: SettingsServiceProtocol
    let stateBoundaryService: StateBoundaryServiceProtocol
    
    /// Creates a container with live implementations of all services
    static func live() -> AppDependencies {
        // Create the settings service first since other services may depend on it
        let settingsService = SettingsService()
        
        // Create a boundary service for state detection
        let boundaryService = StateBoundaryService()
        
        // Create the rest of the services with their dependencies
        let cloudSyncService = CloudSyncService(settings: settingsService)
        let locationService = LocationService(
            settings: settingsService,
            boundaryService: boundaryService
        )
        
        // Create notification service before state detection service
        let notificationService = NotificationService(settings: settingsService)
        
        // Create state detection service with all dependencies including notification service
        let stateDetectionService = StateDetectionService(
            locationService: locationService,
            boundaryService: boundaryService,
            settings: settingsService,
            cloudSync: cloudSyncService,
            notificationService: notificationService
        )
        
        return AppDependencies(
            locationService: locationService,
            stateDetectionService: stateDetectionService,
            cloudSyncService: cloudSyncService,
            notificationService: notificationService,
            settingsService: settingsService,
            stateBoundaryService: boundaryService
        )
    }
    
    /// Creates a container with mock implementations for testing
    static func mock() -> AppDependencies {
        let settingsService = MockSettingsService()
        let boundaryService = MockStateBoundaryService()
        let cloudSyncService = MockCloudSyncService(settings: settingsService)
        let locationService = MockLocationService(
            settings: settingsService,
            boundaryService: boundaryService
        )
        let notificationService = MockNotificationService(settings: settingsService)
        let stateDetectionService = MockStateDetectionService(
            locationService: locationService,
            boundaryService: boundaryService,
            settings: settingsService,
            cloudSync: cloudSyncService,
            notificationService: notificationService
        )
        
        return AppDependencies(
            locationService: locationService,
            stateDetectionService: stateDetectionService,
            cloudSyncService: cloudSyncService,
            notificationService: notificationService,
            settingsService: settingsService,
            stateBoundaryService: boundaryService
        )
    }
    
    /// Private initializer to ensure dependencies are created through factory methods
    private init(
        locationService: LocationServiceProtocol,
        stateDetectionService: StateDetectionServiceProtocol,
        cloudSyncService: CloudSyncServiceProtocol,
        notificationService: NotificationServiceProtocol,
        settingsService: SettingsServiceProtocol,
        stateBoundaryService: StateBoundaryServiceProtocol
    ) {
        self.locationService = locationService
        self.stateDetectionService = stateDetectionService
        self.cloudSyncService = cloudSyncService
        self.notificationService = notificationService
        self.settingsService = settingsService
        self.stateBoundaryService = stateBoundaryService
    }
}

// Extension to make AppDependencies accessible via the environment
extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[DependenciesKey.self] }
        set { self[DependenciesKey.self] = newValue }
    }
}

// Environment key for AppDependencies
private struct DependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies.mock() // Default to mock for previews
}
