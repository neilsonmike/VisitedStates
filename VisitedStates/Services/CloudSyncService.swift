import Foundation
import CloudKit
import Combine
import UIKit
import SwiftUI

// Direct local definition of CloudSettings to fix scope issues
struct CloudSettings: Codable {
    // Notification settings
    var notificationsEnabled: Bool
    var notifyOnlyNewStates: Bool
    
    // Appearance settings
    var stateFillColor: EncodableColor
    var stateStrokeColor: EncodableColor
    var backgroundColor: EncodableColor
    
    // Detection settings
    var speedThreshold: Double
    var altitudeThreshold: Double
    
    // Metadata
    var lastUpdated: Date
    
    // Creates CloudSettings from the current app settings
    static func from(settingsService: SettingsServiceProtocol) -> CloudSettings {
        return CloudSettings(
            notificationsEnabled: settingsService.notificationsEnabled.value,
            notifyOnlyNewStates: settingsService.notifyOnlyNewStates.value,
            stateFillColor: EncodableColor(from: settingsService.stateFillColor.value),
            stateStrokeColor: EncodableColor(from: settingsService.stateStrokeColor.value),
            backgroundColor: EncodableColor(from: settingsService.backgroundColor.value),
            speedThreshold: settingsService.speedThreshold.value,
            altitudeThreshold: settingsService.altitudeThreshold.value,
            lastUpdated: Date()
        )
    }
    
    // Apply these cloud settings to the local settings service
    func applyTo(settingsService: SettingsServiceProtocol) {
        // First check if the user has customized colors since app launch
        let stateFillIsDefault = settingsService.stateFillColor.value == .red
        let stateStrokeIsDefault = settingsService.stateStrokeColor.value == .white
        let backgroundIsDefault = settingsService.backgroundColor.value == .white
        
        // Only apply cloud color settings if the user has not customized them locally
        settingsService.notificationsEnabled.send(notificationsEnabled)
        settingsService.notifyOnlyNewStates.send(notifyOnlyNewStates)
        
        // Preserve custom colors unless they're still at default values
        if stateFillIsDefault {
            settingsService.stateFillColor.send(stateFillColor.toSwiftUIColor())
        }
        if stateStrokeIsDefault {
            settingsService.stateStrokeColor.send(stateStrokeColor.toSwiftUIColor())
        }
        if backgroundIsDefault {
            settingsService.backgroundColor.send(backgroundColor.toSwiftUIColor())
        }
        
        settingsService.speedThreshold.send(speedThreshold)
        settingsService.altitudeThreshold.send(altitudeThreshold)
    }
}

// A structure to make SwiftUI Color codable for cloud storage
struct EncodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double
    
    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
    
    init(from color: Color) {
        // Convert SwiftUI Color to RGB components
        // Use a proxy to ensure opacity is captured correctly
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        // Get RGBA components - if this fails, use reasonable defaults
        if !uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            // Fallback for color models that don't use RGB (like grayscale)
            var white: CGFloat = 0
            if uiColor.getWhite(&white, alpha: &alpha) {
                red = white
                green = white
                blue = white
            } else {
                // Last-resort fallback
                red = 0
                green = 0
                blue = 0
                alpha = 1 // Default to fully opaque if conversion fails
            }
        }
        
        // Store the components
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        // Always enforce at least 0.1 opacity to prevent invisible elements
        self.opacity = max(0.1, Double(alpha))
    }
    
    func toSwiftUIColor() -> Color {
        // Ensure opacity is at least 0.1 to prevent invisible elements
        let safeOpacity = max(0.1, opacity)
        
        // For debugging
        if safeOpacity < 0.99 {
            print("⚠️ Color opacity below 100%: \(safeOpacity * 100)%")
        }
        
        return Color(red: red, green: green, blue: blue, opacity: safeOpacity)
    }
}

class CloudSyncService: CloudSyncServiceProtocol {
    // MARK: - Properties
    
    var syncStatus = CurrentValueSubject<SyncStatus, Never>(.idle)
    
    // Dependencies
    private let settings: SettingsServiceProtocol
    
    // Private state
    private let cloudContainer: CKContainer
    private let privateDatabase: CKDatabase
    
    // Legacy record type for backward compatibility
    private let legacyRecordType = "VisitedStates"
    private let legacyRecordID = CKRecord.ID(recordName: "VisitedStates")
    
    // Enhanced record types for the new model
    private let enhancedRecordType = "EnhancedVisitedStates"
    private let enhancedRecordID = CKRecord.ID(recordName: "EnhancedVisitedStates")
    private let badgesRecordType = "Badges"
    private let badgesRecordID = CKRecord.ID(recordName: "UserBadges")
    
    // Settings record for user preferences
    private let settingsRecordType = "UserSettings"
    private let settingsRecordID = CKRecord.ID(recordName: "UserSettings")
    
    private let syncQueue = DispatchQueue(label: "com.neils.VisitedStates.cloudSync", qos: .utility)
    private var isSyncing = false
    
    // MARK: - Initialization
    
    init(settings: SettingsServiceProtocol, containerIdentifier: String = Constants.cloudContainerID) {
        self.settings = settings
        self.cloudContainer = CKContainer(identifier: containerIdentifier)
        self.privateDatabase = cloudContainer.privateCloudDatabase
        
        // Setup notification observers for app lifecycle events to sync settings
        setupAppStateObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // Setup app state observers for syncing at appropriate times
    private func setupAppStateObservers() {
        // Sync settings when app goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // Fetch settings when app becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        print("☁️ App entering background - syncing settings to cloud")
        syncSettingsToCloud(completion: nil)
    }
    
    @objc private func appDidBecomeActive() {
        print("☁️ App became active - fetching settings from cloud")
        fetchSettingsFromCloud(completion: nil)
    }
    
    // MARK: - CloudSyncServiceProtocol
    
    func syncToCloud(states: [String], completion: ((Result<Void, Error>) -> Void)?) {
        // Prevent concurrent syncs
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If already syncing, queue the completion handler
            guard !self.isSyncing else {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "CloudSyncService", code: 1,
                                                 userInfo: [NSLocalizedDescriptionKey: "Sync already in progress"])))
                }
                return
            }
            
            self.isSyncing = true
            self.syncStatus.send(.syncing)
            
            // Get the enhanced model data
            var visitedStateModels = self.settings.getAllGPSVerifiedStates()
            
            // Add active GPS verified states, avoiding duplicates
            for state in self.settings.getActiveGPSVerifiedStates() {
                if !visitedStateModels.contains(where: { $0.stateName == state.stateName }) {
                    visitedStateModels.append(state)
                }
            }
            
            // Deduplicate by creating a dictionary keyed by state name
            var stateDict: [String: VisitedState] = [:]
            for state in visitedStateModels {
                stateDict[state.stateName] = state
            }
            
            // Convert back to array
            let deduplicatedStates = Array(stateDict.values)
            
            // Get badges from the BadgeTrackingService directly
            let badgeTrackingService = BadgeTrackingService()
            let earnedBadgeDates = badgeTrackingService.getEarnedBadges()
            
            // Convert achievement badges to the Badge format expected by CloudKit
            var badges: [Badge] = []
            
            // For each earned badge ID and date, create a proper Badge object
            for (badgeId, earnedDate) in earnedBadgeDates {
                // Create a CloudKit-compatible Badge object
                let badge = Badge(
                    identifier: badgeId,
                    earnedDate: earnedDate,
                    isEarned: true
                )
                badges.append(badge)
            }
            
            // Only show count summary for better log readability
            print("📤 Syncing to cloud - Enhanced states: \(deduplicatedStates.count), Legacy states: \(states.count), Badges: \(badges.count)")
            print("🏆 Badge IDs being synced: \(badges.map { $0.identifier }.joined(separator: ", "))")
            
            // First sync the enhanced model
            self.syncEnhancedModelToCloud(deduplicatedStates, badges) { enhancedResult in
                // Then sync the legacy format for backward compatibility
                self.syncLegacyFormatToCloud(states) { legacyResult in
                    self.isSyncing = false
                    
                    // If either sync failed, report an error
                    if case .failure(let enhancedError) = enhancedResult {
                        self.syncStatus.send(.failed(enhancedError))
                        DispatchQueue.main.async {
                            completion?(.failure(enhancedError))
                        }
                        return
                    }
                    
                    if case .failure(let legacyError) = legacyResult {
                        self.syncStatus.send(.failed(legacyError))
                        DispatchQueue.main.async {
                            completion?(.failure(legacyError))
                        }
                        return
                    }
                    
                    // Both syncs succeeded
                    self.syncStatus.send(.succeeded)
                    DispatchQueue.main.async {
                        completion?(.success(()))
                    }
                }
            }
        }
    }
    
    func fetchFromCloud(completion: @escaping (Result<[String], Error>) -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard !self.isSyncing else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "CloudSyncService", code: 1,
                                              userInfo: [NSLocalizedDescriptionKey: "Sync already in progress"])))
                }
                return
            }
            
            self.isSyncing = true
            self.syncStatus.send(.syncing)
            
            print("📥 Starting fetch from cloud")
            
            // Use dispatch group to fetch both formats in parallel
            let group = DispatchGroup()
            var enhancedModelResult: Result<([VisitedState], [Badge]), Error>?
            var legacyFormatResult: Result<[String], Error>?
            
            // Fetch enhanced model
            group.enter()
            self.fetchEnhancedModelFromCloud { result in
                enhancedModelResult = result
                group.leave()
            }
            
            // Fetch legacy format at the same time
            group.enter()
            self.fetchLegacyFormatFromCloud { result in
                legacyFormatResult = result
                group.leave()
            }
            
            // Wait for both fetches to complete
            group.notify(queue: self.syncQueue) {
                self.isSyncing = false
                
                // Process the results
                var enhancedStateNames: [String] = []
                var legacyStateNames: [String] = []
                var combinedStateNames: [String] = []
                
                // Handle enhanced model result
                if case let .success((visitedStates, badges)) = enhancedModelResult {
                    print("✅ Successfully fetched enhanced model: \(visitedStates.count) states, \(badges.count) badges")
                    
                    // Deduplicate states by state name
                    var stateDict: [String: VisitedState] = [:]
                    for state in visitedStates {
                        stateDict[state.stateName] = state
                    }
                    let deduplicatedStates = Array(stateDict.values)
                    
                    print("📥 After deduplication: \(deduplicatedStates.count) states")
                    
                    self.processEnhancedModelData(deduplicatedStates, badges)
                    enhancedStateNames = deduplicatedStates.filter { $0.isActive }.map { $0.stateName }
                } else if case let .failure(error) = enhancedModelResult {
                    print("⚠️ Enhanced model fetch failed: \(error.localizedDescription)")
                }
                
                // Handle legacy format result
                if case let .success(stateNames) = legacyFormatResult {
                    print("✅ Successfully fetched legacy format: \(stateNames.count) states")
                    self.processLegacyStateNames(stateNames)
                    legacyStateNames = stateNames
                } else if case let .failure(error) = legacyFormatResult {
                    print("⚠️ Legacy format fetch failed: \(error.localizedDescription)")
                }
                
                // Combine results, giving preference to enhanced model
                if !enhancedStateNames.isEmpty {
                    combinedStateNames = enhancedStateNames
                    
                    // Add legacy states that aren't in enhanced model
                    for state in legacyStateNames {
                        if !combinedStateNames.contains(state) {
                            combinedStateNames.append(state)
                        }
                    }
                    
                    print("📥 Combined \(enhancedStateNames.count) enhanced states and \(legacyStateNames.count) legacy states into \(combinedStateNames.count) unique states")
                } else if !legacyStateNames.isEmpty {
                    // If no enhanced states, just use legacy states
                    combinedStateNames = legacyStateNames
                    print("📥 Using \(legacyStateNames.count) legacy states only")
                } else {
                    // Both formats failed or returned empty results
                    print("⚠️ No states found in cloud")
                }
                
                self.syncStatus.send(.succeeded)
                DispatchQueue.main.async {
                    completion(.success(combinedStateNames))
                }
            }
        }
    }
    
    // MARK: - Settings Synchronization
    
    /// Sync user settings to CloudKit
    func syncSettingsToCloud(completion: ((Result<Void, Error>) -> Void)?) {
        syncQueue.async { [weak self] in
            guard let self = self else {
                completion?(.failure(NSError(domain: "CloudSyncService", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "Service no longer exists"])))
                return
            }
            
            // Don't block state sync if we're already syncing
            if self.isSyncing {
                print("⚠️ Settings sync skipped - another sync already in progress")
                completion?(.failure(NSError(domain: "CloudSyncService", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "Sync already in progress"])))
                return
            }
            
            self.isSyncing = true
            print("📤 Syncing settings to cloud")
            
            // Create CloudSettings from current settings
            let cloudSettings = CloudSettings.from(settingsService: self.settings)
            
            // Encode to JSON
            do {
                let settingsData = try JSONEncoder().encode(cloudSettings)
                guard let settingsJSON = String(data: settingsData, encoding: .utf8) else {
                    throw NSError(domain: "CloudSyncService", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to encode settings as JSON"])
                }
                
                // Save to CloudKit
                self.saveSettingsToCloud(settingsJSON) { result in
                    self.isSyncing = false
                    
                    switch result {
                    case .success:
                        print("✅ Successfully synced settings to cloud")
                        self.syncStatus.send(.succeeded)
                        completion?(.success(()))
                        
                    case .failure(let error):
                        print("⚠️ Failed to sync settings to cloud: \(error.localizedDescription)")
                        self.syncStatus.send(.failed(error))
                        completion?(.failure(error))
                    }
                }
            } catch {
                self.isSyncing = false
                print("⚠️ Error encoding settings: \(error.localizedDescription)")
                self.syncStatus.send(.failed(error))
                completion?(.failure(error))
            }
        }
    }
    
    /// Fetch user settings from CloudKit
    func fetchSettingsFromCloud(completion: ((Result<Void, Error>) -> Void)?) {
        syncQueue.async { [weak self] in
            guard let self = self else {
                completion?(.failure(NSError(domain: "CloudSyncService", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "Service no longer exists"])))
                return
            }
            
            // Don't block state sync if we're already syncing
            if self.isSyncing {
                print("⚠️ Settings fetch skipped - another sync already in progress")
                completion?(.failure(NSError(domain: "CloudSyncService", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "Sync already in progress"])))
                return
            }
            
            self.isSyncing = true
            print("📥 Fetching settings from cloud")
            
            // Fetch settings from CloudKit
            self.fetchSettingsFromCloudKit { result in
                self.isSyncing = false
                
                switch result {
                case .success(let cloudSettings):
                    print("✅ Successfully fetched settings from cloud")
                    
                    // Apply settings to local service (on main thread for UI updates)
                    DispatchQueue.main.async {
                        cloudSettings.applyTo(settingsService: self.settings)
                        print("✅ Applied cloud settings to local app")
                    }
                    
                    self.syncStatus.send(.succeeded)
                    completion?(.success(()))
                    
                case .failure(let error):
                    // No settings found is not an error
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        print("⚠️ No settings found in cloud - this is normal for first use")
                        self.syncStatus.send(.succeeded)
                        completion?(.success(()))
                    } else {
                        print("⚠️ Failed to fetch settings from cloud: \(error.localizedDescription)")
                        self.syncStatus.send(.failed(error))
                        completion?(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Save settings to CloudKit
    private func saveSettingsToCloud(_ settingsJSON: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Fetch or create the record
        privateDatabase.fetch(withRecordID: settingsRecordID) { [weak self] record, error in
            guard let self = self else { return }
            
            var recordToSave: CKRecord
            
            if let existingRecord = record {
                recordToSave = existingRecord
            } else if error != nil && (error as? CKError)?.code != .unknownItem {
                completion(.failure(error!))
                return
            } else {
                recordToSave = CKRecord(recordType: self.settingsRecordType, recordID: self.settingsRecordID)
            }
            
            // Update the record with new data
            recordToSave["settingsJSON"] = settingsJSON as CKRecordValue
            recordToSave["lastUpdated"] = Date() as CKRecordValue
            
            // Save the record
            self.privateDatabase.save(recordToSave) { _, error in
                if let error = error {
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        self.handleSettingsRecordChanged(ckError, settingsJSON: settingsJSON, completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    /// Fetch settings from CloudKit
    private func fetchSettingsFromCloudKit(completion: @escaping (Result<CloudSettings, Error>) -> Void) {
        privateDatabase.fetch(withRecordID: settingsRecordID) { record, error in
            if let error = error {
                if (error as? CKError)?.code == .unknownItem {
                    // No record found - not an error, just return empty settings
                    print("📥 No settings record found in CloudKit")
                    completion(.failure(error))
                    return
                } else {
                    print("⚠️ Error fetching settings: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
            }
            
            guard let record = record, let settingsJSON = record["settingsJSON"] as? String else {
                print("📥 Settings record exists but contains no data")
                completion(.failure(NSError(domain: "CloudSyncService", code: 5,
                                         userInfo: [NSLocalizedDescriptionKey: "Settings record has no data"])))
                return
            }
            
            // Decode the JSON data
            guard let data = settingsJSON.data(using: .utf8) else {
                completion(.failure(NSError(domain: "CloudSyncService", code: 5,
                                         userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON to data"])))
                return
            }
            
            do {
                let settings = try JSONDecoder().decode(CloudSettings.self, from: data)
                print("📥 Successfully decoded settings from CloudKit")
                completion(.success(settings))
            } catch {
                print("⚠️ Error decoding settings JSON: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /// Handle conflicts with server-side changes for settings data
    private func handleSettingsRecordChanged(_ error: CKError, settingsJSON: String,
                                            completion: @escaping (Result<Void, Error>) -> Void) {
        guard let serverRecord = error.serverRecord else {
            completion(.failure(error))
            return
        }
        
        // Get server data
        guard let serverSettingsJSON = serverRecord["settingsJSON"] as? String,
              let serverData = serverSettingsJSON.data(using: .utf8),
              let localData = settingsJSON.data(using: .utf8) else {
            // If server data can't be parsed, overwrite it with our data
            saveSettingsToCloud(settingsJSON, completion: completion)
            return
        }
        
        // Try to decode server and local data
        do {
            let serverSettings = try JSONDecoder().decode(CloudSettings.self, from: serverData)
            let localSettings = try JSONDecoder().decode(CloudSettings.self, from: localData)
            
            // Merge server and local settings
            let mergedSettings = mergeCloudSettings(local: localSettings, cloud: serverSettings)
            
            // Encode the merged data
            let mergedData = try JSONEncoder().encode(mergedSettings)
            guard let mergedJSON = String(data: mergedData, encoding: .utf8) else {
                completion(.failure(NSError(domain: "CloudSyncService", code: 6,
                                         userInfo: [NSLocalizedDescriptionKey: "Failed to encode merged settings"])))
                return
            }
            
            // Save the merged data
            saveSettingsToCloud(mergedJSON, completion: completion)
            
        } catch {
            // If data can't be decoded, use our local data
            saveSettingsToCloud(settingsJSON, completion: completion)
        }
    }
    
    /// Merge local and cloud settings
    private func mergeCloudSettings(local: CloudSettings, cloud: CloudSettings) -> CloudSettings {
        // Create a new settings object based on the newest data
        let useLocalSettings = local.lastUpdated > cloud.lastUpdated
        var result = useLocalSettings ? local : cloud
        
        // Special opacity handling to avoid invisible colors
        result.stateFillColor.opacity = max(0.5, local.stateFillColor.opacity, cloud.stateFillColor.opacity)
        result.stateStrokeColor.opacity = max(0.5, local.stateStrokeColor.opacity, cloud.stateStrokeColor.opacity)
        result.backgroundColor.opacity = max(0.5, local.backgroundColor.opacity, cloud.backgroundColor.opacity)
        
        // Log the settings merge
        if useLocalSettings {
            print("📥 Using local settings (newer than cloud), with opacity fixes")
            print("📥 State fill opacity: \(result.stateFillColor.opacity)")
            print("📥 State stroke opacity: \(result.stateStrokeColor.opacity)")
            print("📥 Background opacity: \(result.backgroundColor.opacity)")
        } else {
            print("📥 Using cloud settings (newer than local), with opacity fixes")
            print("📥 State fill opacity: \(result.stateFillColor.opacity)")
            print("📥 State stroke opacity: \(result.stateStrokeColor.opacity)")
            print("📥 Background opacity: \(result.backgroundColor.opacity)")
        }
        
        // Update lastUpdated
        result.lastUpdated = Date()
        
        return result
    }
    
    // MARK: - Enhanced Model Sync
    
    /// Sync the enhanced model (VisitedState and Badge objects) to CloudKit
    private func syncEnhancedModelToCloud(_ visitedStates: [VisitedState], _ badges: [Badge],
                                        completion: @escaping (Result<Void, Error>) -> Void) {
        // Encode the model data as JSON
        do {
            let statesData = try JSONEncoder().encode(visitedStates)
            let badgesData = try JSONEncoder().encode(badges)
            
            guard let statesJSON = String(data: statesData, encoding: .utf8),
                  let badgesJSON = String(data: badgesData, encoding: .utf8) else {
                throw NSError(domain: "CloudSyncService", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to encode data as JSON"])
            }
            
            // Use a dispatch group to synchronize multiple operations
            let group = DispatchGroup()
            var syncError: Error?
            
            // Sync visited states
            group.enter()
            saveEnhancedStateDataToCloud(statesJSON) { result in
                if case .failure(let error) = result {
                    syncError = error
                }
                group.leave()
            }
            
            // Sync badges
            group.enter()
            saveBadgeDataToCloud(badgesJSON) { result in
                if case .failure(let error) = result {
                    syncError = error
                }
                group.leave()
            }
            
            // Wait for both operations to complete
            group.notify(queue: syncQueue) {
                if let error = syncError {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    /// Save the enhanced state data to CloudKit
    private func saveEnhancedStateDataToCloud(_ statesJSON: String,
                                            completion: @escaping (Result<Void, Error>) -> Void) {
        // Fetch or create the record
        privateDatabase.fetch(withRecordID: enhancedRecordID) { [weak self] record, error in
            guard let self = self else { return }
            
            var recordToSave: CKRecord
            
            if let existingRecord = record {
                recordToSave = existingRecord
            } else if error != nil && (error as? CKError)?.code != .unknownItem {
                completion(.failure(error!))
                return
            } else {
                recordToSave = CKRecord(recordType: self.enhancedRecordType, recordID: self.enhancedRecordID)
            }
            
            // Update the record with new data
            recordToSave["statesJSON"] = statesJSON as CKRecordValue
            recordToSave["lastUpdated"] = Date() as CKRecordValue
            
            // Save the record
            self.privateDatabase.save(recordToSave) { _, error in
                if let error = error {
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        self.handleEnhancedStateRecordChanged(ckError, statesJSON: statesJSON, completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    /// Save badge data to CloudKit
    private func saveBadgeDataToCloud(_ badgesJSON: String,
                                    completion: @escaping (Result<Void, Error>) -> Void) {
        // Debug the JSON being sent to CloudKit
        print("🏆 Badge JSON for CloudKit: \(badgesJSON)")
        
        // If the badgesJSON is "[]", check if we have any badges to sync
        if badgesJSON == "[]" {
            // Get badges from BadgeTrackingService directly instead of using settings
            let badgeTrackingService = BadgeTrackingService()
            let earnedBadgeDates = badgeTrackingService.getEarnedBadges()
            
            // Convert to Badge objects
            var newBadges: [Badge] = []
            for (badgeId, earnedDate) in earnedBadgeDates {
                newBadges.append(Badge(
                    identifier: badgeId,
                    earnedDate: earnedDate,
                    isEarned: true
                ))
            }
            
            print("🏆 BadgeTrackingService reports \(newBadges.count) earned badges, but JSON is empty array")
            
            // If we do have badges but JSON is empty, let's fix it
            if !newBadges.isEmpty {
                print("🏆 Fixing empty badge JSON with data from BadgeTrackingService")
                
                // Create a new JSON string for badges
                do {
                    let badgeData = try JSONEncoder().encode(newBadges)
                    let newBadgesJSON = String(data: badgeData, encoding: .utf8)!
                    
                    // Replace the empty JSON with our new one
                    return saveBadgeDataToCloud(newBadgesJSON, completion: completion)
                } catch {
                    print("⚠️ Error creating badge JSON: \(error.localizedDescription)")
                }
            }
        }
        
        // Fetch or create the record
        privateDatabase.fetch(withRecordID: badgesRecordID) { [weak self] record, error in
            guard let self = self else { return }
            
            var recordToSave: CKRecord
            
            if let existingRecord = record {
                recordToSave = existingRecord
                print("📱 Using existing badge record in CloudKit")
                
                // Debug existing content
                if let existingJSON = existingRecord["badgesJSON"] as? String {
                    print("📱 Existing badgesJSON in CloudKit: \(existingJSON)")
                }
            } else if error != nil && (error as? CKError)?.code != .unknownItem {
                print("⚠️ Error fetching badge record: \(error!.localizedDescription)")
                completion(.failure(error!))
                return
            } else {
                recordToSave = CKRecord(recordType: self.badgesRecordType, recordID: self.badgesRecordID)
                print("📱 Created new badge record in CloudKit")
            }
            
            // Only update if we have meaningful badge data
            if badgesJSON != "[]" || recordToSave["badgesJSON"] == nil {
                // Update the record with new data
                recordToSave["badgesJSON"] = badgesJSON as CKRecordValue
                recordToSave["lastUpdated"] = Date() as CKRecordValue
                
                print("📱 Updating badge record with new data")
                
                // Save the record
                self.privateDatabase.save(recordToSave) { savedRecord, error in
                    if let error = error {
                        if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                            print("⚠️ Server record changed conflict for badges")
                            self.handleBadgeRecordChanged(ckError, badgesJSON: badgesJSON, completion: completion)
                        } else {
                            print("⚠️ Error saving badge record: \(error.localizedDescription)")
                            completion(.failure(error))
                        }
                    } else {
                        print("✅ Successfully saved badge record to CloudKit")
                        
                        // Verify what was saved
                        if let savedJSON = savedRecord?["badgesJSON"] as? String {
                            print("✅ Saved badgesJSON: \(savedJSON)")
                        }
                        
                        completion(.success(()))
                    }
                }
            } else {
                print("⚠️ Skipping badge sync - empty badge array and record already exists")
                completion(.success(()))
            }
        }
    }
    
    /// Fetch the enhanced model data from CloudKit
    private func fetchEnhancedModelFromCloud(
        completion: @escaping (Result<([VisitedState], [Badge]), Error>) -> Void) {
        
        // Use a dispatch group to fetch both states and badges
        let group = DispatchGroup()
        var visitedStates: [VisitedState]?
        var badges: [Badge]?
        var fetchError: Error?
        
        // Fetch the enhanced state data
        group.enter()
        fetchEnhancedStatesFromCloud { result in
            switch result {
            case .success(let states):
                print("📥 Fetched \(states.count) states from cloud")
                visitedStates = states
            case .failure(let error):
                print("⚠️ Error fetching states: \(error.localizedDescription)")
                fetchError = error
            }
            group.leave()
        }
        
        // Fetch the badges data
        group.enter()
        fetchBadgesFromCloud { result in
            switch result {
            case .success(let badgesData):
                print("📥 Fetched \(badgesData.count) badges from cloud")
                badges = badgesData
            case .failure(let error):
                print("⚠️ Error fetching badges: \(error.localizedDescription)")
                if fetchError == nil {
                    fetchError = error
                }
            }
            group.leave()
        }
        
        // Wait for both fetches to complete
        group.notify(queue: syncQueue) {
            if let error = fetchError {
                completion(.failure(error))
            } else if let states = visitedStates, let badges = badges {
                completion(.success((states, badges)))
            } else {
                // This shouldn't happen if both fetches succeed
                completion(.failure(NSError(domain: "CloudSyncService", code: 4,
                                          userInfo: [NSLocalizedDescriptionKey: "Failed to fetch data"])))
            }
        }
    }
    
    /// Fetch the enhanced state data from CloudKit
    private func fetchEnhancedStatesFromCloud(completion: @escaping (Result<[VisitedState], Error>) -> Void) {
        privateDatabase.fetch(withRecordID: enhancedRecordID) { record, error in
            if let error = error {
                if (error as? CKError)?.code == .unknownItem {
                    // No record found - not an error, just return empty array
                    print("📥 No enhanced states record found in CloudKit")
                    completion(.success([]))
                } else {
                    print("⚠️ Error fetching enhanced states: \(error.localizedDescription)")
                    completion(.failure(error))
                }
                return
            }
            
            guard let record = record, let statesJSON = record["statesJSON"] as? String else {
                print("📥 Enhanced states record exists but contains no data")
                completion(.success([]))
                return
            }
            
            // Decode the JSON data
            guard let data = statesJSON.data(using: .utf8) else {
                completion(.failure(NSError(domain: "CloudSyncService", code: 5,
                                          userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON to data"])))
                return
            }
            
            do {
                let states = try JSONDecoder().decode([VisitedState].self, from: data)
                print("📥 Successfully decoded \(states.count) states from CloudKit")
                
                // Check for duplicates
                let stateNames = states.map { $0.stateName }
                let uniqueStateNames = Set(stateNames)
                if stateNames.count != uniqueStateNames.count {
                    print("⚠️ Found duplicate states in CloudKit data: \(stateNames.count) total states, \(uniqueStateNames.count) unique states")
                    
                    // Deduplicate
                    var stateDict: [String: VisitedState] = [:]
                    for state in states {
                        stateDict[state.stateName] = state
                    }
                    let deduplicatedStates = Array(stateDict.values)
                    print("📥 Deduplicated to \(deduplicatedStates.count) states")
                    
                    completion(.success(deduplicatedStates))
                } else {
                    completion(.success(states))
                }
            } catch {
                print("⚠️ Error decoding states JSON: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /// Fetch badge data from CloudKit
    private func fetchBadgesFromCloud(completion: @escaping (Result<[Badge], Error>) -> Void) {
        privateDatabase.fetch(withRecordID: badgesRecordID) { record, error in
            if let error = error {
                if (error as? CKError)?.code == .unknownItem {
                    // No record found - not an error, just return empty array
                    print("📥 No badges record found in CloudKit")
                    completion(.success([]))
                } else {
                    print("⚠️ Error fetching badges: \(error.localizedDescription)")
                    completion(.failure(error))
                }
                return
            }
            
            guard let record = record, let badgesJSON = record["badgesJSON"] as? String else {
                print("📥 Badges record exists but contains no data")
                completion(.success([]))
                return
            }
            
            // Decode the JSON data
            guard let data = badgesJSON.data(using: .utf8) else {
                completion(.failure(NSError(domain: "CloudSyncService", code: 5,
                                          userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON to data"])))
                return
            }
            
            do {
                let badges = try JSONDecoder().decode([Badge].self, from: data)
                print("📥 Successfully decoded \(badges.count) badges from CloudKit")
                completion(.success(badges))
            } catch {
                print("⚠️ Error decoding badges JSON: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /// Handle conflicts with server-side changes for enhanced state data
    private func handleEnhancedStateRecordChanged(_ error: CKError, statesJSON: String,
                                                completion: @escaping (Result<Void, Error>) -> Void) {
        guard let serverRecord = error.serverRecord else {
            completion(.failure(error))
            return
        }
        
        // Get server data
        guard let serverStatesJSON = serverRecord["statesJSON"] as? String,
              let serverData = serverStatesJSON.data(using: .utf8),
              let localData = statesJSON.data(using: .utf8) else {
            // If server data can't be parsed, overwrite it with our data
            saveEnhancedStateDataToCloud(statesJSON, completion: completion)
            return
        }
        
        // Try to decode server and local data
        do {
            let serverStates = try JSONDecoder().decode([VisitedState].self, from: serverData)
            let localStates = try JSONDecoder().decode([VisitedState].self, from: localData)
            
            // Deduplicate server states
            var serverStateDict: [String: VisitedState] = [:]
            for state in serverStates {
                serverStateDict[state.stateName] = state
            }
            let deduplicatedServerStates = Array(serverStateDict.values)
            
            // Deduplicate local states
            var localStateDict: [String: VisitedState] = [:]
            for state in localStates {
                localStateDict[state.stateName] = state
            }
            let deduplicatedLocalStates = Array(localStateDict.values)
            
            // Merge server and local data
            let mergedStates = mergeVisitedStates(local: deduplicatedLocalStates, cloud: deduplicatedServerStates)
            
            // Encode the merged data
            let mergedData = try JSONEncoder().encode(mergedStates)
            guard let mergedJSON = String(data: mergedData, encoding: .utf8) else {
                completion(.failure(NSError(domain: "CloudSyncService", code: 6,
                                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode merged data"])))
                return
            }
            
            // Save the merged data
            saveEnhancedStateDataToCloud(mergedJSON, completion: completion)
            
        } catch {
            // If data can't be decoded, use our local data
            saveEnhancedStateDataToCloud(statesJSON, completion: completion)
        }
    }
    
    /// Handle conflicts with server-side changes for badge data
    private func handleBadgeRecordChanged(_ error: CKError, badgesJSON: String,
                                        completion: @escaping (Result<Void, Error>) -> Void) {
        guard let serverRecord = error.serverRecord else {
            completion(.failure(error))
            return
        }
        
        // Get server data
        guard let serverBadgesJSON = serverRecord["badgesJSON"] as? String,
              let serverData = serverBadgesJSON.data(using: .utf8),
              let localData = badgesJSON.data(using: .utf8) else {
            // If server data can't be parsed, overwrite it with our data
            saveBadgeDataToCloud(badgesJSON, completion: completion)
            return
        }
        
        // Try to decode server and local data
        do {
            let serverBadges = try JSONDecoder().decode([Badge].self, from: serverData)
            let localBadges = try JSONDecoder().decode([Badge].self, from: localData)
            
            // Merge server and local data
            let mergedBadges = mergeBadges(local: localBadges, cloud: serverBadges)
            
            // Encode the merged data
            let mergedData = try JSONEncoder().encode(mergedBadges)
            guard let mergedJSON = String(data: mergedData, encoding: .utf8) else {
                completion(.failure(NSError(domain: "CloudSyncService", code: 6,
                                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode merged data"])))
                return
            }
            
            // Save the merged data
            saveBadgeDataToCloud(mergedJSON, completion: completion)
            
        } catch {
            // If data can't be decoded, use our local data
            saveBadgeDataToCloud(badgesJSON, completion: completion)
        }
    }
    
    /// Merge local and cloud VisitedState arrays
    private func mergeVisitedStates(local: [VisitedState], cloud: [VisitedState]) -> [VisitedState] {
        var merged: [String: VisitedState] = [:]
        
        // Add all local states to the merged dictionary
        for state in local {
            merged[state.stateName] = state
        }
        
        // Merge with cloud states
        for cloudState in cloud {
            if let localState = merged[cloudState.stateName] {
                // State exists locally, merge the two
                merged[cloudState.stateName] = mergeVisitedState(local: localState, cloud: cloudState)
            } else {
                // State doesn't exist locally, add the cloud version
                merged[cloudState.stateName] = cloudState
            }
        }
        
        // Convert back to array
        return Array(merged.values)
    }
    
    /// Merge a single VisitedState from local and cloud
    private func mergeVisitedState(local: VisitedState, cloud: VisitedState) -> VisitedState {
        var result = local
        
        // Prioritize GPS-verification status
        result.visited = local.visited || cloud.visited
        result.wasEverVisited = local.wasEverVisited || cloud.wasEverVisited
        
        // Prioritize edited status
        result.edited = local.edited || cloud.edited
        
        // Use the earliest first visited date
        if let localFirst = local.firstVisitedDate,
           let cloudFirst = cloud.firstVisitedDate {
            result.firstVisitedDate = localFirst < cloudFirst ? localFirst : cloudFirst
        } else {
            result.firstVisitedDate = local.firstVisitedDate ?? cloud.firstVisitedDate
        }
        
        // Use the latest last visited date
        if let localLast = local.lastVisitedDate,
           let cloudLast = cloud.lastVisitedDate {
            result.lastVisitedDate = localLast > cloudLast ? localLast : cloudLast
        } else {
            result.lastVisitedDate = local.lastVisitedDate ?? cloud.lastVisitedDate
        }
        
        // Prioritize active status
        result.isActive = local.isActive || cloud.isActive
        
        return result
    }
    
    /// Merge local and cloud Badge arrays
    private func mergeBadges(local: [Badge], cloud: [Badge]) -> [Badge] {
        var merged: [String: Badge] = [:]
        
        // Add all local badges to the merged dictionary
        for badge in local {
            merged[badge.identifier] = badge
        }
        
        // Merge with cloud badges
        for cloudBadge in cloud {
            if let localBadge = merged[cloudBadge.identifier] {
                // Badge exists locally, merge the two
                merged[cloudBadge.identifier] = mergeBadge(local: localBadge, cloud: cloudBadge)
            } else {
                // Badge doesn't exist locally, add the cloud version
                merged[cloudBadge.identifier] = cloudBadge
            }
        }
        
        // Convert back to array
        return Array(merged.values)
    }
    
    /// Merge a single Badge from local and cloud
    private func mergeBadge(local: Badge, cloud: Badge) -> Badge {
        // If either the local or cloud version is earned, the merged version is earned
        let isEarned = local.isEarned || cloud.isEarned
        
        // Use the earliest earned date if both are earned
        var earnedDate: Date? = nil
        if isEarned {
            if let localDate = local.earnedDate, let cloudDate = cloud.earnedDate {
                earnedDate = localDate < cloudDate ? localDate : cloudDate
            } else {
                earnedDate = local.earnedDate ?? cloud.earnedDate
            }
        }
        
        return Badge(identifier: local.identifier, earnedDate: earnedDate, isEarned: isEarned)
    }
    
    /// Process fetched enhanced model data
    private func processEnhancedModelData(_ visitedStates: [VisitedState], _ badges: [Badge]) {
        print("🔄 Processing \(visitedStates.count) fetched states and \(badges.count) badges")
        // Update the settings service with the fetched data
        
        // First, count how many states were manually edited vs. GPS-verified
        var manualEditCount = 0
        var gpsVerifiedCount = 0
        var activeCount = 0
        
        // Loop through each state and use appropriate setting method
        for state in visitedStates {
            if state.wasEverVisited {
                // If it was ever GPS-verified, use addStateViaGPS
                self.settings.addStateViaGPS(state.stateName)
                gpsVerifiedCount += 1
            } else if state.edited {
                // If it was manually edited, use addVisitedState
                self.settings.addVisitedState(state.stateName)
                manualEditCount += 1
            }
            
            // If the state should not be active, remove it
            if !state.isActive {
                self.settings.removeVisitedState(state.stateName)
            } else {
                activeCount += 1
            }
        }
        
        print("🔄 Processed states: \(gpsVerifiedCount) GPS-verified, \(manualEditCount) manually edited, \(activeCount) active")
        
        // Process badges - save them in the BadgeTrackingService
        var earnedBadgeCount = 0
        let badgeTrackingService = BadgeTrackingService()
        
        // First get existing viewed badges to maintain their status
        let viewedBadges = badgeTrackingService.getViewedBadges()
        
        for badge in badges {
            if badge.isEarned {
                earnedBadgeCount += 1
                
                // Check if this badge was previously viewed
                let hasBeenViewed = viewedBadges.contains(badge.identifier)
                
                // Save the badge in the BadgeTrackingService, preserving the earned date
                badgeTrackingService.saveEarnedBadge(
                    id: badge.identifier,
                    date: badge.earnedDate ?? Date(),
                    visitedStates: [] // We don't have this info from the cloud sync
                )
                
                // If it was previously viewed, make sure it doesn't show as new
                if hasBeenViewed {
                    var newBadges = badgeTrackingService.getNewBadges()
                    if let index = newBadges.firstIndex(of: badge.identifier) {
                        newBadges.remove(at: index)
                        UserDefaults.standard.set(newBadges, forKey: "new_badges")
                    }
                }
            }
        }
        
        print("🔄 Processed \(earnedBadgeCount) earned badges")
        
        // If we found any badges, update the UI to show them as new
        if earnedBadgeCount > 0 {
            print("🏆 Updating badge data from cloud - \(earnedBadgeCount) badges synchronized")
        }
    }
    
    /// Process legacy state names by creating basic VisitedState models
    private func processLegacyStateNames(_ stateNames: [String]) {
        print("🔄 Processing \(stateNames.count) legacy state names")
        
        // Mark all fetched states from legacy format as manually edited
        print("🔄 Processing \(stateNames.count) legacy states as manually edited")

        // Instead of logging every state individually, just process them
        for state in stateNames {
            self.settings.addVisitedState(state)
            
            // Create or update an enhanced model for this state
            let existingStates = self.settings.getAllGPSVerifiedStates() + self.settings.getActiveGPSVerifiedStates()
            if !existingStates.contains(where: { $0.stateName == state }) {
                // Only manually add if not already in enhanced model
                _ = VisitedState(
                    stateName: state,
                    visited: false,
                    edited: true,
                    firstVisitedDate: Date(),
                    lastVisitedDate: Date(),
                    isActive: true,
                    wasEverVisited: false
                )
                
                // TODO: When full Enhanced model UI is implemented, update this
                // For now, we just mark it as a manually edited state without verbose logging
                // New enhanced models created for states that don't have them yet
            }
        }
    }
    
    // MARK: - Legacy Format Sync
    
    /// Sync the legacy format (array of state names) to CloudKit
    private func syncLegacyFormatToCloud(_ states: [String],
                                       completion: @escaping (Result<Void, Error>) -> Void) {
        // First fetch existing record if any
        privateDatabase.fetch(withRecordID: legacyRecordID) { [weak self] record, error in
            guard let self = self else { return }
            
            // Fixed: Create a local variable for the record
            var recordToSave: CKRecord
            
            if let existingRecord = record {
                // Update existing record
                recordToSave = existingRecord
            } else if error != nil && (error as? CKError)?.code != .unknownItem {
                // Handle errors other than "record not found"
                completion(.failure(error!))
                return
            } else {
                // Create new record if none exists
                recordToSave = CKRecord(recordType: self.legacyRecordType, recordID: self.legacyRecordID)
            }
            
            // Update record with new states
            recordToSave["states"] = states as CKRecordValue
            recordToSave["lastUpdated"] = Date() as CKRecordValue
            
            // Save record
            self.privateDatabase.save(recordToSave) { _, error in
                if let error = error {
                    // Handle CloudKit specific errors
                    if let ckError = error as? CKError {
                        switch ckError.code {
                        case .serverRecordChanged:
                            // Handle conflict with server-side changes
                            self.handleLegacyServerRecordChanged(ckError, states: states, completion: completion)
                            return
                        case .networkFailure, .networkUnavailable, .serviceUnavailable:
                            // Retry for network issues after a delay
                            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                                self.syncLegacyFormatToCloud(states, completion: completion)
                            }
                            return
                        default:
                            break
                        }
                    }
                    
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    /// Fetch the legacy format (array of state names) from CloudKit
    private func fetchLegacyFormatFromCloud(completion: @escaping (Result<[String], Error>) -> Void) {
        let query = CKQuery(recordType: legacyRecordType, predicate: NSPredicate(value: true))
        
        // Use API based on iOS version
        if #available(iOS 15.0, *) {
            privateDatabase.fetch(withQuery: query, inZoneWith: nil) { [weak self] result in
                guard self != nil else { return }
                
                switch result {
                case .success(let (matchResults, _)):
                    guard !matchResults.isEmpty else {
                        print("📥 No legacy records found in CloudKit")
                        completion(.success([]))
                        return
                    }
                    
                    // Extract states from all records
                    var allStates: [String] = []
                    for (_, matchResult) in matchResults {
                        switch matchResult {
                        case .success(let record):
                            if let states = record["states"] as? [String] {
                                allStates.append(contentsOf: states)
                            }
                        case .failure:
                            continue
                        }
                    }
                    
                    // Remove duplicates
                    let uniqueStates = Array(Set(allStates))
                    print("📥 Fetched \(uniqueStates.count) unique states from legacy format")
                    completion(.success(uniqueStates))
                    
                case .failure(let error):
                    print("⚠️ Error fetching legacy format: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        } else {
            // Fallback for older iOS versions
            privateDatabase.perform(query, inZoneWith: nil) { results, error in
                if let error = error {
                    print("⚠️ Error fetching legacy format: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let records = results, !records.isEmpty else {
                    // No records found - this is not an error, just return empty array
                    print("📥 No legacy records found in CloudKit (iOS < 15)")
                    completion(.success([]))
                    return
                }
                
                // Extract states from all records, if multiple exist (should be just one)
                var allStates: [String] = []
                
                for record in records {
                    if let states = record["states"] as? [String] {
                        allStates.append(contentsOf: states)
                    }
                }
                
                // Remove duplicates
                let uniqueStates = Array(Set(allStates))
                print("📥 Fetched \(uniqueStates.count) unique states from legacy format (iOS < 15)")
                completion(.success(uniqueStates))
            }
        }
    }
    
    /// Handle conflicts with server-side changes for legacy format
    private func handleLegacyServerRecordChanged(_ error: CKError, states: [String],
                                             completion: @escaping (Result<Void, Error>) -> Void) {
        guard let serverRecord = error.serverRecord else {
            completion(.failure(error))
            return
        }
        
        // Get server states
        let serverStates = serverRecord["states"] as? [String] ?? []
        
        // Merge with local states
        let mergedStates = Array(Set(serverStates + states))
        
        // Create a new record with the merged states
        let newRecord = CKRecord(recordType: legacyRecordType, recordID: legacyRecordID)
        newRecord["states"] = mergedStates as CKRecordValue
        newRecord["lastUpdated"] = Date() as CKRecordValue
        
        // Save using the server record as the ancestor
        let modifyOp = CKModifyRecordsOperation(
            recordsToSave: [newRecord],
            recordIDsToDelete: nil
        )
        
        modifyOp.savePolicy = .changedKeys
        
        // Use API based on iOS version
        if #available(iOS 15.0, *) {
            modifyOp.modifyRecordsResultBlock = { result in
                switch result {
                case .success(_):
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Fallback for older iOS
            modifyOp.modifyRecordsCompletionBlock = { savedRecords, _, error in
                if let error = error {
                    completion(.failure(error))
                } else if savedRecords != nil {
                    completion(.success(()))
                } else {
                    completion(.failure(NSError(domain: "CloudSyncService", code: 2,
                                              userInfo: [NSLocalizedDescriptionKey: "Unknown error during sync"])))
                }
            }
        }
        
        privateDatabase.add(modifyOp)
    }
}
