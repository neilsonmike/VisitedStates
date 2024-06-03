import Foundation
import CoreLocation
import CloudKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var lastGeocodeRequestTime: Date?

    @Published var currentLocation: CLLocation? {
        didSet {
            if let location = currentLocation {
                updateVisitedStates(location: location)
            }
        }
    }

    @Published var visitedStates: [String] = [] {
        didSet {
            saveVisitedStates()
        }
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        checkLocationAuthorization()
    }

    func checkLocationAuthorization() {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager did fail with error: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
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

            if let placemark = placemarks?.first, let stateAbbreviation = placemark.administrativeArea {
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
    }

    func saveVisitedStates() {
        let record = CKRecord(recordType: "VisitedStates")
        record["states"] = visitedStates as CKRecordValue
        let privateDatabase = CKContainer.default().privateCloudDatabase
        privateDatabase.save(record) { record, error in
            if let error = error {
                print("Error saving visited states: \(error)")
            } else {
                print("Visited states saved successfully")
            }
        }
    }

    func loadVisitedStates() {
        let privateDatabase = CKContainer.default().privateCloudDatabase
        let query = CKQuery(recordType: "VisitedStates", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)

        var loadedStates: [String] = []

        operation.recordFetchedBlock = { record in
            if let states = record["states"] as? [String] {
                loadedStates = states
            }
        }

        operation.queryCompletionBlock = { cursor, error in
            if let error = error as? CKError, error.code == .notAuthenticated {
                print("Failed to load visited states: \(error)")
                // Prompt the user to sign in to iCloud or handle the error appropriately
            } else if let error = error {
                print("Failed to load visited states: \(error)")
            } else {
                DispatchQueue.main.async {
                    self.visitedStates = loadedStates
                    print("Loaded visited states: \(loadedStates)")
                }
            }
        }

        privateDatabase.add(operation)
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
