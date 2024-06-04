import Foundation
import CoreLocation
import CloudKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var lastGeocodeRequestTime: Date?
    private var lastLocationUpdateTime: Date?
    private let userDefaultsKey = "visitedStates"
    private var isSyncing = false
    private var isSavingLocally = false
    private var syncTimer: Timer?
    private var syncInterval: TimeInterval = 300  // 5 minutes

    @Published var currentLocation: CLLocation? {
        didSet {
            if let location = currentLocation {
                updateVisitedStates(location: location)
            }
        }
    }

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

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100  // Adjust the distance filter if needed
        loadVisitedStates()
        checkLocationAuthorization()
    }

    func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("Location services are restricted or denied")
        @unknown default:
            print("Unknown location authorization status")
        }
    }

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
            print("Location Manager did fail with error: \(error.localizedDescription)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let currentTime = Date()
        
        if let lastUpdateTime = lastLocationUpdateTime, currentTime.timeIntervalSince(lastUpdateTime) < 10 {
            return
        }
        
        lastLocationUpdateTime = currentTime
        currentLocation = location
        print("Updated location: \(location)")
        updateVisitedStates(location: location)
    }

    func updateVisitedStates(location: CLLocation) {
        let currentTime = Date()
        // Check if the last request was made more than 30 seconds ago
        if let lastRequestTime = lastGeocodeRequestTime, currentTime.timeIntervalSince(lastRequestTime) < 30 {
            return
        }

        lastGeocodeRequestTime = currentTime

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] (placemarks, error) in
            if let error = error {
                print("Reverse geocoding failed with error: \(error.localizedDescription)")
                return
            }
            
            guard let placemark = placemarks?.first, let stateAbbreviation = placemark.administrativeArea else {
                print("No valid placemark found.")
                return
            }
            
            print("Current state: \(stateAbbreviation)")
            
            guard let fullStateName = self?.stateAbbreviationToFullName(stateAbbreviation) else {
                print("State abbreviation \(stateAbbreviation) not found in mapping")
                return
            }
            
            if !(self?.visitedStates.contains(fullStateName) ?? false) {
                self?.visitedStates.append(fullStateName)
                print("Visited states: \(self?.visitedStates ?? [])")
            }
        }
    }

    func saveVisitedStates() {
        isSavingLocally = true
        UserDefaults.standard.set(visitedStates, forKey: userDefaultsKey)
        isSavingLocally = false
        print("Visited states saved locally")
    }

    func loadVisitedStates() {
        if let savedStates = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            visitedStates = savedStates
            print("Loaded visited states from local storage: \(savedStates)")
        } else {
            visitedStates = []
            print("No visited states found in local storage")
        }
        syncWithCloudKit()
    }

    func scheduleSyncWithCloudKit() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: false) { [weak self] _ in
            self?.syncWithCloudKit()
        }
    }

    func syncWithCloudKit() {
        isSyncing = true
        let privateDatabase = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        let query = CKQuery(recordType: "VisitedStates", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)

        var cloudVisitedStates: [String] = []

        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let states = record["states"] as? [String] {
                    cloudVisitedStates = states
                }
            case .failure(let error):
                print("Failed to fetch record: \(error)")
            }
        }

        operation.queryResultBlock = { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    // Merge local and cloud states, respecting CloudKit as the source of truth
                    self.mergeCloudStates(cloudVisitedStates)
                    self.isSyncing = false
                }
            case .failure(let error):
                print("Failed to load visited states: \(error)")
                self.isSyncing = false
            }
        }

        privateDatabase.add(operation)
    }

    func mergeCloudStates(_ cloudStates: [String]) {
        // Combine local and cloud states, respecting CloudKit as the source of truth
        let combinedStates = Array(Set(cloudStates + visitedStates))
        
        // Update local storage to reflect the merged states
        visitedStates = combinedStates
        saveVisitedStates()
        print("Merged local and cloud states: \(combinedStates)")

        // Save combined states to CloudKit
        saveToCloudKit(combinedStates)
    }

    func saveToCloudKit(_ states: [String]) {
        let privateDatabase = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "VisitedStates")
        
        // Fetch the current record to get the latest changes
        privateDatabase.fetch(withRecordID: recordID) { [weak self] fetchedRecord, error in
            if let error = error {
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    // Record does not exist, create a new one
                    let record = CKRecord(recordType: "VisitedStates", recordID: recordID)
                    record["states"] = states as CKRecordValue
                    self?.saveRecordToCloudKit(record)
                } else {
                    print("Error fetching record from CloudKit: \(error)")
                }
                return
            }
            
            if let record = fetchedRecord {
                // Update the fetched record with the new states
                record["states"] = states as CKRecordValue
                self?.saveRecordToCloudKit(record)
            }
        }
    }

    func saveRecordToCloudKit(_ record: CKRecord) {
        let privateDatabase = CKContainer(identifier: "iCloud.me.neils.VisitedStates").privateCloudDatabase
        
        privateDatabase.save(record) { savedRecord, error in
            if let error = error {
                if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                    // Handle server record changed error
                    print("Server record changed. Fetching latest record and retrying save.")
                    self.handleServerRecordChanged(record, error: ckError)
                } else {
                    print("Error saving visited states to CloudKit: \(error)")
                }
            } else {
                print("Visited states saved to CloudKit")
            }
        }
    }

    func handleServerRecordChanged(_ record: CKRecord, error: CKError) {
        if let serverRecord = error.serverRecord {
            // Merge local changes with server record
            serverRecord["states"] = record["states"]
            // Save the merged record to CloudKit
            saveRecordToCloudKit(serverRecord)
        } else {
            print("Failed to handle server record changed error: \(error)")
        }
    }

    func stateAbbreviationToFullName(_ abbreviation: String) -> String? {
        let stateNames = [
            "AL": "Alabama",
            "AK": "Alaska",
            "AZ": "Arizona",
            "AR": "Arkansas",
            "CA": "California",
            "CO": "Colorado",
            "CT": "Connecticut",
            "DE": "Delaware",
            "FL": "Florida",
            "GA": "Georgia",
            "HI": "Hawaii",
            "ID": "Idaho",
            "IL": "Illinois",
            "IN": "Indiana",
            "IA": "Iowa",
            "KS": "Kansas",
            "KY": "Kentucky",
            "LA": "Louisiana",
            "ME": "Maine",
            "MD": "Maryland",
            "MA": "Massachusetts",
            "MI": "Michigan",
            "MN": "Minnesota",
            "MS": "Mississippi",
            "MO": "Missouri",
            "MT": "Montana",
            "NE": "Nebraska",
            "NV": "Nevada",
            "NH": "New Hampshire",
            "NJ": "New Jersey",
            "NM": "New Mexico",
            "NY": "New York",
            "NC": "North Carolina",
            "ND": "North Dakota",
            "OH": "Ohio",
            "OK": "Oklahoma",
            "OR": "Oregon",
            "PA": "Pennsylvania",
            "RI": "Rhode Island",
            "SC": "South Carolina",
            "SD": "South Dakota",
            "TN": "Tennessee",
            "TX": "Texas",
            "UT": "Utah",
            "VT": "Vermont",
            "VA": "Virginia",
            "WA": "Washington",
            "WV": "West Virginia",
            "WI": "Wisconsin",
            "WY": "Wyoming"
        ]
        return stateNames[abbreviation]
    }
}
