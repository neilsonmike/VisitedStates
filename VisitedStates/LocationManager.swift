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

    private var lastNotifiedState: String? {
        get { UserDefaults.standard.string(forKey: "lastNotifiedState") }
        set { UserDefaults.standard.set(newValue, forKey: "lastNotifiedState") }
    }

    private var previousDetectedState: String? {
        get { UserDefaults.standard.string(forKey: "previousDetectedState") }
        set { UserDefaults.standard.set(newValue, forKey: "previousDetectedState") }
    }

    private var lastProcessedLocation: CLLocation?

    @Published var visitedStates: [String] = [] {
        didSet {
            if !isSavingLocally { saveVisitedStates() }
        }
    }

    @Published var currentLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100

        loadVisitedStates()
        checkLocationAuthorization()
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

    func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startStandardLocationUpdates()
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
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

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager error: \(error.localizedDescription)")
    }

    var bgTask: UIBackgroundTaskIdentifier = .invalid

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    bgTask = UIApplication.shared.beginBackgroundTask(withName: "CloudKitSync") {
        print("⚠️ Background task expired. Ending task explicitly.")
        UIApplication.shared.endBackgroundTask(self.bgTask)
        self.bgTask = .invalid
    }
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
        if self.bgTask != .invalid {
            print("⚠️ Background task timeout explicitly reached, ending task.")
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = .invalid
        }
    }

        guard let location = locations.last else {
        UIApplication.shared.endBackgroundTask(self.bgTask)
            return
        }

    updateVisitedStates(location: location) {
        if self.bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = .invalid
        }
    }
    }

    func hasVisitedState(_ state: String) -> Bool {
        return visitedStates.contains(state)
    }

    func updateVisitedStates(location: CLLocation, completion: @escaping () -> Void) {
        guard let fullStateName = StateBoundaryManager.shared.stateName(for: location.coordinate) else {
            completion()
            return
        }

        DispatchQueue.main.async {
            var authoritativeStates = AppSettings.shared.visitedStates

            if !authoritativeStates.contains(fullStateName) {
                authoritativeStates.append(fullStateName)
                AppSettings.shared.visitedStates = authoritativeStates

                self.syncLocalStatesToCloudKit(localStates: authoritativeStates) {
                    completion()
                }
            } else {
                completion()
            }

            if self.lastNotifiedState != fullStateName {
                NotificationManager.shared.handleDetectedState(fullStateName)
                self.lastNotifiedState = fullStateName
            }
        }
        
        if self.previousDetectedState != fullStateName {
            print("State change detected: from \(self.previousDetectedState ?? "nil") to \(fullStateName)")
            self.previousDetectedState = fullStateName
            self.lastNotifiedState = nil
        }
    }
    
    func saveVisitedStates() {
        isSavingLocally = true
        UserDefaults.standard.set(visitedStates, forKey: userDefaultsKey)
        isSavingLocally = false
        print("Visited states saved locally: \(visitedStates)")
    }

    func loadVisitedStates() {
        if let savedStates = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            visitedStates = savedStates
        } else {
            visitedStates = []
        }
        syncWithCloudKit()
    }


    func syncWithCloudKit() {
        print("Starting sync with CloudKit.")
        isSyncing = true
        let privateDB = CKContainer(identifier: Constants.cloudContainerID).privateCloudDatabase
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
            DispatchQueue.main.async {
                if case .success = result {
                    self.mergeCloudStates(cloudVisited)
                }
                self.isSyncing = false
            }
        }
        privateDB.add(operation)
    }

    func mergeCloudStates(_ cloudStates: [String]) {
        if self.visitedStates.isEmpty, !cloudStates.isEmpty {
            visitedStates = cloudStates
        }
        self.syncLocalStatesToCloudKit(localStates: visitedStates)
    }

    // Synchronize local visited states with CloudKit.
    func syncLocalStatesToCloudKit(localStates: [String], completion: (() -> Void)? = nil) {
        let privateDB = CKContainer(identifier: Constants.cloudContainerID).privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "VisitedStates")

        // Explicitly fetch existing record first
        privateDB.fetch(withRecordID: recordID) { existingRecord, fetchError in
            let record: CKRecord

            if let existingRecord = existingRecord {
                // Explicitly update existing record
                record = existingRecord
            } else {
                // Explicitly create new record if none exists
                record = CKRecord(recordType: "VisitedStates", recordID: recordID)
            }

            record["states"] = localStates as CKRecordValue
            record["lastUpdated"] = Date()

            privateDB.save(record) { savedRecord, error in
                if let error = error {
                    print("CloudKit sync error: \(error.localizedDescription)")
                } else {
                    print("Successfully synced states explicitly: \(localStates)")
                }
                completion?()
            }
        }
    }

    // Handle server-side merge conflicts.
    func handleServerRecordChanged(_ record: CKRecord, error: CKError) {
        let privateDB = CKContainer(identifier: Constants.cloudContainerID).privateCloudDatabase
        privateDB.fetch(withRecordID: record.recordID) { fetchedRecord, fetchError in
            if let fetchError = fetchError {
                print("Error fetching record from CloudKit: \(fetchError)")
                return
            }
            if let serverRecord = fetchedRecord {
                // Explicitly use AppSettings authoritative data here:
                let authoritativeStates = AppSettings.shared.visitedStates
                serverRecord["states"] = authoritativeStates as CKRecordValue
                serverRecord["lastUpdated"] = Date()
                self.saveRecordToCloudKit(serverRecord)
                print("☁️ Conflict resolved explicitly with authoritative states: \(authoritativeStates)")
            }
        }
    }

    // Persist resolved states back to CloudKit.
    func saveRecordToCloudKit(_ record: CKRecord) {
        let privateDB = CKContainer(identifier: Constants.cloudContainerID).privateCloudDatabase
        privateDB.save(record) { savedRecord, error in
            if let error = error {
                print("Error saving visited states to CloudKit: \(error)")
            } else {
                print("Visited states saved to CloudKit (server record changed flow).")
            }
        }
    }
}
