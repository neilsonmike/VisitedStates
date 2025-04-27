import Foundation
import CloudKit
import Combine

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
    
    private let syncQueue = DispatchQueue(label: "com.neils.VisitedStates.cloudSync", qos: .utility)
    private var isSyncing = false
    
    // MARK: - Initialization
    
    init(settings: SettingsServiceProtocol, containerIdentifier: String = Constants.cloudContainerID) {
        self.settings = settings
        self.cloudContainer = CKContainer(identifier: containerIdentifier)
        self.privateDatabase = cloudContainer.privateCloudDatabase
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
            
            // Get badges
            let badges = self.settings.getEarnedBadges()
            
            print("📤 Syncing to cloud - Enhanced states: \(deduplicatedStates.count), Legacy states: \(states.count), Badges: \(badges.count)")
            print("📤 Enhanced states to sync: \(deduplicatedStates.map { $0.stateName }.joined(separator: ", "))")
            print("📤 Legacy states to sync: \(states.joined(separator: ", "))")
            
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
                    print("📥 States from enhanced model: \(deduplicatedStates.map { $0.stateName }.joined(separator: ", "))")
                    
                    self.processEnhancedModelData(deduplicatedStates, badges)
                    enhancedStateNames = deduplicatedStates.filter { $0.isActive }.map { $0.stateName }
                } else if case let .failure(error) = enhancedModelResult {
                    print("⚠️ Enhanced model fetch failed: \(error.localizedDescription)")
                }
                
                // Handle legacy format result
                if case let .success(stateNames) = legacyFormatResult {
                    print("✅ Successfully fetched legacy format: \(stateNames.count) states")
                    print("📥 States from legacy format: \(stateNames.joined(separator: ", "))")
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
        // Fetch or create the record
        privateDatabase.fetch(withRecordID: badgesRecordID) { [weak self] record, error in
            guard let self = self else { return }
            
            var recordToSave: CKRecord
            
            if let existingRecord = record {
                recordToSave = existingRecord
            } else if error != nil && (error as? CKError)?.code != .unknownItem {
                completion(.failure(error!))
                return
            } else {
                recordToSave = CKRecord(recordType: self.badgesRecordType, recordID: self.badgesRecordID)
            }
            
            // Update the record with new data
            recordToSave["badgesJSON"] = badgesJSON as CKRecordValue
            recordToSave["lastUpdated"] = Date() as CKRecordValue
            
            // Save the record
            self.privateDatabase.save(recordToSave) { _, error in
                if let error = error {
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        self.handleBadgeRecordChanged(ckError, badgesJSON: badgesJSON, completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                } else {
                    completion(.success(()))
                }
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
        
        // Process badges
        var earnedBadgeCount = 0
        for badge in badges {
            if badge.isEarned {
                earnedBadgeCount += 1
                // TODO: Process badges when badge UI is implemented
            }
        }
        
        print("🔄 Processed \(earnedBadgeCount) earned badges")
    }
    
    /// Process legacy state names by creating basic VisitedState models
    private func processLegacyStateNames(_ stateNames: [String]) {
        print("🔄 Processing \(stateNames.count) legacy state names")
        
        // Mark all fetched states from legacy format as manually edited
        print("🔄 Adding legacy states as manually edited: \(stateNames.joined(separator: ", "))")
        for state in stateNames {
            print("🔄 Adding manually edited state: \(state)")
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
                // For now, we just mark it as a manually edited state
                print("🔄 Creating new enhanced model for manually edited state: \(state)")
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
