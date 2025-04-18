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
    private let recordType = "VisitedStates"
    private let recordID = CKRecord.ID(recordName: "VisitedStates")
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
            
            self.saveStatesToCloud(states) { result in
                self.isSyncing = false
                
                switch result {
                case .success:
                    self.syncStatus.send(.succeeded)
                    DispatchQueue.main.async {
                        completion?(.success(()))
                    }
                    
                case .failure(let error):
                    self.syncStatus.send(.failed(error))
                    DispatchQueue.main.async {
                        completion?(.failure(error))
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
            
            self.fetchStatesFromCloud { result in
                self.isSyncing = false
                
                switch result {
                case .success(let states):
                    self.syncStatus.send(.succeeded)
                    DispatchQueue.main.async {
                        completion(.success(states))
                    }
                    
                case .failure(let error):
                    self.syncStatus.send(.failed(error))
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    // MARK: - Private methods
    
    private func saveStatesToCloud(_ states: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        // First fetch existing record if any
        privateDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
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
                recordToSave = CKRecord(recordType: self.recordType, recordID: self.recordID)
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
                            self.handleServerRecordChanged(ckError, states: states, completion: completion)
                            return
                        case .networkFailure, .networkUnavailable, .serviceUnavailable:
                            // Retry for network issues after a delay
                            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                                self.saveStatesToCloud(states, completion: completion)
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
    
    private func fetchStatesFromCloud(completion: @escaping (Result<[String], Error>) -> Void) {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        
        // Use API based on iOS version
        if #available(iOS 15.0, *) {
            privateDatabase.fetch(withQuery: query, inZoneWith: nil) { [weak self] result in
                guard self != nil else { return }
                
                switch result {
                case .success(let (matchResults, _)):
                    guard !matchResults.isEmpty else {
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
                    completion(.success(uniqueStates))
                    
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Fallback for older iOS versions
            privateDatabase.perform(query, inZoneWith: nil) { results, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let records = results, !records.isEmpty else {
                    // No records found - this is not an error, just return empty array
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
                completion(.success(uniqueStates))
            }
        }
    }
    
    private func handleServerRecordChanged(_ error: CKError, states: [String],
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
        let newRecord = CKRecord(recordType: recordType, recordID: recordID)
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
