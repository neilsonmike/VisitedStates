import Foundation
import CoreLocation
import CloudKit
import UIKit
import SwiftUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let locationManager = CLLocationManager()
    private var lastGeocodeRequestTime: Date?
    private var lastLocationUpdateTime: Date?
    private let userDefaultsKey = "visitedStates"
    private var isSyncing = false
    private var isSavingLocally = false
    private var syncTimer: Timer?
    private var syncInterval: TimeInterval = 300  // 5 minutes

    private let speedThreshold: CLLocationSpeed = 44.7
    private let altitudeThreshold: CLLocationDistance = 3048
    
    private var lastNotifiedState: String? {
        get {
            UserDefaults.standard.string(forKey: "lastNotifiedState")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastNotifiedState")
        }
    }

    /// The single source of truth for visited states.
    @Published var visitedStates: [String] = [] {
        didSet {
            if !isSavingLocally {
                saveVisitedStates()
            }
            if !isSyncing {
                scheduleSyncWithCloudKit()
            }
        }
    }

    @Published var currentLocation: CLLocation? {
        didSet {
            if let location = currentLocation {
                updateVisitedStates(location: location)
            }
        }
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100
        
        loadVisitedStates()
        checkLocationAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Authorization & App State
    
    func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startStandardLocationUpdates()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("Location services are restricted or denied")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    @objc private func appDidEnterBackground() {
        locationManager.stopUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        print("Switched to significant location updates (background)")
    }
    
    @objc private func appDidBecomeActive() {
        locationManager.stopMonitoringSignificantLocationChanges()
        startStandardLocationUpdates()
        print("Switched to standard location updates (foreground)")
    }
    
    private func startStandardLocationUpdates() {
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = CLError(_nsError: error as NSError)
        switch clError.code {
        case .locationUnknown:
            print("Location unknown.")
        case .denied:
            print("Access to location services denied.")
        case .network:
            print("Network error.")
        default:
            print("Location Manager error: \(error.localizedDescription)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    print("📍 Location update received at \(Date())")
        
        // Check altitude
        if location.altitude > altitudeThreshold {
            print("Ignoring location update above altitude: \(location.altitude) m")
            return
        }
        
        // Check speed
        if location.speed >= 0 && location.speed > speedThreshold {
            print("Ignoring location update above speed: \(location.speed) m/s")
            return
        }
        
        let currentTime = Date()
        if let lastUpdateTime = lastLocationUpdateTime,
           currentTime.timeIntervalSince(lastUpdateTime) < 10 {
            print("⚠️ Ignored location update due to timing restriction.")
            return
        } else {
            lastLocationUpdateTime = currentTime
        }
        
        currentLocation = location
        print("Updated location: \(location)")
        updateVisitedStates(location: location)
    }
    
    // MARK: - Reverse Geocode & Visited States
    
    func hasVisitedState(_ state: String) -> Bool {
        return visitedStates.contains(state)
    }
    
    
    func updateVisitedStates(location: CLLocation) {
        guard let fullStateName = StateBoundaryManager.shared.stateName(for: location.coordinate) else {
            print("State not found using GeoJSON-based lookup")
            return
        }
        
        // Only trigger notification and CloudKit updates if state has changed
        if fullStateName != self.lastNotifiedState {
            if !self.visitedStates.contains(fullStateName) {
                self.visitedStates.append(fullStateName)
            }
            NotificationManager.shared.handleDetectedState(fullStateName)
            self.lastNotifiedState = fullStateName
        } else {
            print("Already notified for state \(fullStateName). Skipping notification.")
        }
    }
    
    // MARK: - Local Storage
    
    func saveVisitedStates() {
        isSavingLocally = true
        UserDefaults.standard.set(visitedStates, forKey: userDefaultsKey)
        isSavingLocally = false
        print("Visited states saved locally: \(visitedStates)")
    }
    
    func loadVisitedStates() {
        if let savedStates = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            visitedStates = savedStates
            print("Loaded visited states from local storage: \(savedStates)")
        } else {
            visitedStates = []
            print("No visited states found in local storage.")
        }
        // Then do an initial sync from cloud
        syncWithCloudKit()
    }
    
    // MARK: - CloudKit Sync
    
    func scheduleSyncWithCloudKit() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: false) { [weak self] _ in
            self?.syncWithCloudKit()
        }
    }
    
    func syncWithCloudKit() {
        print("Starting sync with CloudKit.")
        isSyncing = true
        
        let privateDB = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        let query = CKQuery(recordType: "VisitedStates", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        
        var cloudVisited: [String] = []
        
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let states = record["states"] as? [String] {
                    cloudVisited.append(contentsOf: states)
                }
            case .failure(let error):
                print("Failed to fetch record: \(error)")
            }
        }
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    print("Fetched from CloudKit: \(cloudVisited)")
                    self.mergeCloudStates(cloudVisited)
                    self.isSyncing = false
                }
            case .failure(let error):
                print("Failed to load visited states: \(error)")
                self.isSyncing = false
            }
        }
        privateDB.add(operation)
    }
    
    /// Local is final: We do NOT do a union. Instead, if local has removed states, we remove them from the cloud too.
    /// So if the user un-checked a state, that state won't re-appear from the cloud.
    func mergeCloudStates(_ cloudStates: [String]) {
        // If local is empty and cloud has data, let's adopt the cloud on first load
        // (only if user hasn't visited states at all). Otherwise, local overrides.
        if visitedStates.isEmpty, !cloudStates.isEmpty {
            visitedStates = cloudStates
            print("Local was empty; adopting cloud states: \(cloudStates)")
        } else {
            // local overrides, so do nothing to visitedStates here
            print("Local states override cloud. Local = \(visitedStates)")
        }
        
        // Now overwrite the cloud record with local states
        syncLocalStatesToCloudKit(localStates: visitedStates, cloudStates: cloudStates)
    }
    
    /// We overwrite the CloudKit record's "states" with local states
    func syncLocalStatesToCloudKit(localStates: [String], cloudStates: [String]) {
        let privateDB = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        
        // We'll always create/update a single record named "VisitedStates"
        let recordID = CKRecord.ID(recordName: "VisitedStates")
        let record = CKRecord(recordType: "VisitedStates", recordID: recordID)
        
        // Overwrite states with local
        record["states"] = localStates as CKRecordValue
        record["lastUpdated"] = Date()
        
        privateDB.save(record) { savedRecord, error in
            if let error = error {
                if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                    print("Server record changed. We'll fetch & re-merge.")
                    self.handleServerRecordChanged(record, error: ckError)
                } else {
                    print("Error saving to CloudKit: \(error)")
                }
            } else {
                print("Successfully wrote local states to CloudKit: \(localStates)")
            }
        }
    }
    
    func handleServerRecordChanged(_ record: CKRecord, error: CKError) {
        let privateDB = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        privateDB.fetch(withRecordID: record.recordID) { fetchedRecord, fetchError in
            if let fetchError = fetchError {
                print("Error fetching record from CloudKit: \(fetchError)")
                return
            }
            if let serverRecord = fetchedRecord {
                // In the old logic, we appended. Now we treat local as final:
                serverRecord["states"] = self.visitedStates as CKRecordValue
                serverRecord["lastUpdated"] = Date()
                self.saveRecordToCloudKit(serverRecord)
            }
        }
    }
    
    func saveRecordToCloudKit(_ record: CKRecord) {
        let privateDB = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        privateDB.save(record) { savedRecord, error in
            if let error = error {
                print("Error saving visited states to CloudKit: \(error)")
            } else {
                print("Visited states saved to CloudKit (server record changed flow).")
            }
        }
    }
    
    // MARK: - Clear data
    
    func clearLocalData() {
        visitedStates = []
        saveVisitedStates()
        print("Local data cleared.")
        syncWithCloudKit()  // reload from CloudKit
    }
    
    func clearAllData() {
        visitedStates = []
        saveVisitedStates()
        clearCloudKitData()
        print("All data cleared from local & CloudKit.")
    }
    
    func clearCloudKitData() {
        let privateDB = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        let query = CKQuery(recordType: "VisitedStates", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        var recordIDsToDelete: [CKRecord.ID] = []
        
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                recordIDsToDelete.append(record.recordID)
            case .failure(let error):
                print("Failed to fetch record: \(error)")
            }
        }
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                let deleteOp = CKModifyRecordsOperation(recordsToSave: nil,
                                                        recordIDsToDelete: recordIDsToDelete)
                deleteOp.modifyRecordsCompletionBlock = { saved, deleted, error in
                    if let error = error {
                        print("Error deleting from CloudKit: \(error)")
                    } else {
                        print("Deleted records from CloudKit.")
                    }
                }
                privateDB.add(deleteOp)
            case .failure(let error):
                print("Failed to load visited states: \(error)")
            }
        }
        privateDB.add(operation)
    }
    
}
