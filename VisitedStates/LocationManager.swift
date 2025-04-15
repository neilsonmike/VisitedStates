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

    // Persist the last notified state in UserDefaults.
    private var lastNotifiedState: String? {
        get { UserDefaults.standard.string(forKey: "lastNotifiedState") }
        set { UserDefaults.standard.set(newValue, forKey: "lastNotifiedState") }
    }
    
    // Persist the previous detected state in UserDefaults so it survives force quit.
    private var previousDetectedState: String? {
        get { UserDefaults.standard.string(forKey: "previousDetectedState") }
        set { UserDefaults.standard.set(newValue, forKey: "previousDetectedState") }
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
        // Removed: locationManager.allowsBackgroundLocationUpdates = true
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
            // Request Always Authorization if possible
            locationManager.requestAlwaysAuthorization()
        case .restricted, .denied:
            print("Location services are restricted or denied")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    @objc private func appDidEnterBackground() {
        locationManager.stopUpdatingLocation()
        // Use significant location changes in background; no need for standard updates.
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
        
        // Set current location. (The didSet on currentLocation calls updateVisitedStates.)
        currentLocation = location
        print("Updated location: \(location)")
    }
    
    // MARK: - Reverse Geocode & Visited States
    func hasVisitedState(_ state: String) -> Bool {
        return visitedStates.contains(state)
    }
    
    func updateVisitedStates(location: CLLocation) {
        // Get the state name using StateBoundaryManager's lookup (GeoJSON based)
        guard let fullStateName = StateBoundaryManager.shared.stateName(for: location.coordinate) else {
            print("State not found using GeoJSON-based lookup")
            return
        }
        print("Polygon lookup returned state: \(fullStateName)")
        
        DispatchQueue.main.async {
            // If not active (background), update persistence and notify if needed.
            if UIApplication.shared.applicationState != .active {
                if !self.visitedStates.contains(fullStateName) {
                    self.visitedStates.append(fullStateName)
                    print("App in background: Added \(fullStateName) to visitedStates")
                    self.saveVisitedStates()
                } else {
                    print("App in background: \(fullStateName) is already in visitedStates")
                }
                if self.lastNotifiedState != fullStateName {
                    NotificationManager.shared.handleDetectedState(fullStateName)
                    self.lastNotifiedState = fullStateName
                } else {
                    print("App in background: Already notified for \(fullStateName); skipping notification.")
                }
                return
            }
            
            // For active state:
            if self.previousDetectedState != fullStateName {
                print("State change detected: from \(self.previousDetectedState ?? "nil") to \(fullStateName)")
                self.previousDetectedState = fullStateName
                self.lastNotifiedState = nil
            }
            
            if self.lastNotifiedState == nil {
                if !self.visitedStates.contains(fullStateName) {
                    self.visitedStates.append(fullStateName)
                }
                NotificationManager.shared.handleDetectedState(fullStateName)
                self.lastNotifiedState = fullStateName
                print("State \(fullStateName) (new or re-entered) detected; notification triggered.")
            } else {
                print("Already notified for state \(fullStateName). Forcing UI update without duplicate notification.")
                self.visitedStates = Array(self.visitedStates)
            }
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
    
    func mergeCloudStates(_ cloudStates: [String]) {
        if visitedStates.isEmpty, !cloudStates.isEmpty {
            visitedStates = cloudStates
            print("Local was empty; adopting cloud states: \(cloudStates)")
        } else {
            print("Local states override cloud. Local = \(visitedStates)")
        }
        syncLocalStatesToCloudKit(localStates: visitedStates, cloudStates: cloudStates)
    }
    
    func syncLocalStatesToCloudKit(localStates: [String], cloudStates: [String]) {
        let privateDB = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "VisitedStates")
        let record = CKRecord(recordType: "VisitedStates", recordID: recordID)
        
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
                let deleteOp = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDsToDelete)
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
