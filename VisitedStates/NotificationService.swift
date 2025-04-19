import Foundation
import UserNotifications
import Combine
import CloudKit
import UIKit
import Network

class NotificationService: NSObject, NotificationServiceProtocol, UNUserNotificationCenterDelegate {
    // MARK: - Properties
    
    var isNotificationsAuthorized = CurrentValueSubject<Bool, Never>(false)
    
    // Dependencies
    private let settings: SettingsServiceProtocol
    
    // Private state
    private let userNotificationCenter: UNUserNotificationCenter
    private let cloudContainer: CKContainer
    private let publicDatabase: CKDatabase
    private let notificationDelay: TimeInterval = 2.0 // Increased delay for better background delivery
    private var lastNotifiedState: String? {
        get {
            return UserDefaults.standard.string(forKey: "lastNotifiedState")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastNotifiedState")
        }
    }
    private var notificationCooldowns: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 300 // 5 minutes
    private let cooldownKeyPrefix = "lastNotified_"
    private var notificationBackgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]
    
    // DEBUG: Network monitor
    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable: Bool = false
    
    // Cache management
    private let factoidCacheAge: TimeInterval = 7 * 24 * 3600 // 1 week
    private var lastFactoidFetchTime: Date? {
        get {
            return UserDefaults.standard.object(forKey: "lastFactoidFetchTime") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastFactoidFetchTime")
        }
    }
    
    // Fallback factoids when cloud fetch fails
    private let fallbackFactoids: [String: [String]] = [
        "Generic": [
            "Did you know? This state has its own unique history and culture!",
            "Fun fact: Every state has something special to discover!",
            "This state has its own unique landmarks and natural beauty!",
            "Each state contributes something special to America!",
            "This state has its own fascinating stories to tell!"
        ]
    ]
    
    // Cached factoids to handle offline scenarios
    private var cachedFactoids: [String: [String]] = [:]
    private var isPreloadingFactoids = false
    private var factoidFetchTasks: [String: UIBackgroundTaskIdentifier] = [:]
    
    // DEBUG: Count of factoid sources used
    private var factoidSourceStats: [String: Int] = [
        "cloudKit": 0,
        "stateCache": 0,
        "genericCache": 0,
        "fallback": 0
    ]
    
    // MARK: - Initialization
    
    init(
        settings: SettingsServiceProtocol,
        notificationCenter: UNUserNotificationCenter = UNUserNotificationCenter.current(),
        containerIdentifier: String = Constants.cloudContainerID
    ) {
        self.settings = settings
        self.userNotificationCenter = notificationCenter
        self.cloudContainer = CKContainer(identifier: containerIdentifier)
        self.publicDatabase = cloudContainer.publicCloudDatabase
        
        super.init()
        
        // Set up network monitoring
        setupNetworkMonitoring()
        
        userNotificationCenter.delegate = self
        checkNotificationAuthorization()
        
        // Preload factoids for offline use
        preloadFactoids()
        
        // Register notification categories and actions
        registerNotificationCategories()
        
        print("🔔 NotificationService initialized")
        
        // DEBUG: Log cached factoid stats
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.logCachedFactoidStats()
        }
    }
    
    deinit {
        networkMonitor?.cancel()
    }
    
    // MARK: - NotificationServiceProtocol
    
    func requestNotificationPermissions() {
        userNotificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            guard let self = self else { return }
            
            if let error = error {
                print("⚠️ Notification permission error: \(error.localizedDescription)")
            }
            
            // Update authorization status
            DispatchQueue.main.async {
                self.isNotificationsAuthorized.send(granted)
                
                if granted {
                    // If permissions were just granted, preload factoids
                    self.preloadFactoids()
                    print("✅ Notification permission granted")
                } else {
                    print("⚠️ Notification permission denied")
                }
            }
        }
    }
    
    func handleDetectedState(_ state: String) {
        print("🔔 Handling detection of state: \(state)")
        
        // Always notify for state changes, regardless of whether the state has been visited before
        if shouldNotifyForState(state) {
            print("🔔 Will notify for state: \(state)")
            scheduleStateEntryNotification(for: state)
        } else {
            print("🔔 Skipping notification for \(state) - cooldown or same as last state")
        }
    }
    
    func scheduleStateEntryNotification(for state: String) {
        // Create a background task for notification process
        let bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask(for: state)
        }
        
        // Store the task ID
        notificationBackgroundTasks[state] = bgTask
        
        // Skip if notifications are disabled
        guard settings.notificationsEnabled.value else {
            print("🔔 Notifications are disabled in settings. Skipping.")
            endBackgroundTask(for: state)
            return
        }
        
        // Skip if same as last notified (to prevent duplicates)
        if state == lastNotifiedState {
            print("🔔 \(state) was just notified. Preventing duplicate.")
            endBackgroundTask(for: state)
            return
        }
        
        // Check cooldown
        let key = cooldownKeyPrefix + state
        if let lastNotified = UserDefaults.standard.object(forKey: key) as? Date {
            let timeSince = Date().timeIntervalSince(lastNotified)
            if timeSince < cooldownInterval {
                print("🔔 Notification for \(state) is on cooldown. Time since last: \(timeSince)s")
                endBackgroundTask(for: state)
                return
            }
        }
        
        print("🔔 Starting notification process for \(state)")
        
        // DEBUG: Log network status before fetch
        print("🌐 Network status before fetch: \(isNetworkAvailable ? "Available" : "Unavailable")")
        print("🌐 Additional connection check: \(checkInternetConnection() ? "Connected" : "Disconnected")")
        
        // Fetch factoid with priority on CloudKit and fall back to cache
        fetchFactoidWithPriority(for: state) { [weak self] factoid in
            guard let self = self else {
                UIApplication.shared.endBackgroundTask(bgTask)
                return
            }
            
            // Use the factoid or a default welcome message
            let factText = factoid ?? "Welcome to \(state)!"
            
            // DEBUG: Log the factoid content to help identify source
            print("📊 Factoid selected: \"\(factText)\"")
            print("📊 Factoid source stats: \(self.factoidSourceStats)")
            
            // Schedule notification with time delay for better background delivery
            self.sendEnhancedNotification(for: state, fact: factText)
            
            // Update tracking
            UserDefaults.standard.set(Date(), forKey: key)
            
            // Update the persistent last notified state
            self.lastNotifiedState = state
            print("🔔 Updated persistent last notified state to: \(state)")
            
            // Keep the background task running until notification is scheduled
            // The notification completion handler will end it
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Present notifications even when app is in foreground
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification interactions here if needed
        completionHandler()
    }
    
    // MARK: - Private methods
    
    // DEBUG: Set up network monitoring
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
                print("🌐 Network status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
                print("🌐 Connection details: \(path.debugDescription)")
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
    }
    
    private func checkNotificationAuthorization() {
        userNotificationCenter.getNotificationSettings { [weak self] settings in
            let isAuthorized = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                self?.isNotificationsAuthorized.send(isAuthorized)
                print("🔔 Notification authorization status: \(isAuthorized)")
            }
        }
    }
    
    private func registerNotificationCategories() {
        // Create a category for state entry notifications with actions
        let viewMapAction = UNNotificationAction(
            identifier: "VIEW_MAP",
            title: "View Map",
            options: .foreground
        )
        
        let stateEntryCategory = UNNotificationCategory(
            identifier: "STATE_ENTRY",
            actions: [viewMapAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register the category
        userNotificationCenter.setNotificationCategories([stateEntryCategory])
    }
    
    private func shouldNotifyForState(_ state: String) -> Bool {
        // Check for persistent last notified state match first
        // This handles the app kill/relaunch scenario
        if state == lastNotifiedState {
            print("🔔 Skip notification - matches persistent last notified state: \(state)")
            return false
        }
        
        // Check cooldown period
        let key = cooldownKeyPrefix + state
        if let lastNotified = UserDefaults.standard.object(forKey: key) as? Date {
            let timeSince = abs(Date().timeIntervalSince(lastNotified))
            let shouldNotify = timeSince >= cooldownInterval
            
            if !shouldNotify {
                print("🔔 Skip notification - cooldown period active for \(state): \(Int(timeSince))s of \(Int(cooldownInterval))s")
            }
            
            return shouldNotify
        }
        
        print("🔔 Notification allowed for \(state) - not last notified state and no cooldown active")
        // No previous notification for this state
        return true
    }
    
    private func sendEnhancedNotification(for state: String, fact: String) {
        print("🔔 Preparing enhanced notification for \(state)")
        
        let content = UNMutableNotificationContent()
        content.title = "Welcome to \(state)!"
        content.body = fact
        content.sound = UNNotificationSound.default
        
        // Add time-sensitive notification settings for better background delivery
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        
        // Add the state as a category identifier for potential actions
        content.categoryIdentifier = "STATE_ENTRY"
        
        // Use a time interval trigger with increased delay for better background delivery
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: notificationDelay,
            repeats: false
        )
        
        let requestID = "stateNotification_\(state)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: trigger
        )
        
        userNotificationCenter.add(request) { [weak self] error in
            if let error = error {
                print("⚠️ Error scheduling notification for \(state): \(error.localizedDescription)")
            } else {
                print("✅ Notification scheduled for \(state)")
            }
            
            // End the background task
            self?.endBackgroundTask(for: state)
        }
    }
    
    private func endBackgroundTask(for state: String) {
        if let taskID = notificationBackgroundTasks[state], taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
            notificationBackgroundTasks.removeValue(forKey: state)
            print("🔔 Ended background task for notification: \(state)")
        }
    }
    
    private func preloadFactoids() {
        // Avoid multiple concurrent preloads
        guard !isPreloadingFactoids else { return }
        
        // Check if we've preloaded recently
        if let lastFetch = lastFactoidFetchTime,
           Date().timeIntervalSince(lastFetch) < factoidCacheAge {
            // If the cache is less than a week old, just load from local storage
            print("🔍 Using recent factoid cache (age: \(Int(Date().timeIntervalSince(lastFetch)/3600))h)")
            loadCachedFactoids()
            return
        }
        
        isPreloadingFactoids = true
        
        print("🔍 Preloading state factoids for all states...")
        print("🌐 Network status before preload: \(isNetworkAvailable ? "Available" : "Unavailable")")
        
        // Create query for all factoids
        let query = CKQuery(recordType: "StateFactoids", predicate: NSPredicate(value: true))
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 100 // Get a good batch
        
        var fetchedRecords = [CKRecord]()
        
        operation.recordMatchedBlock = { (_, result) in
            switch result {
            case .success(let record):
                fetchedRecords.append(record)
            case .failure(let error):
                print("⚠️ Record fetch failed: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                // Process the fetched records
                for record in fetchedRecords {
                    if let state = record["state"] as? String,
                       let fact = record["fact"] as? String {
                        // Add to cached factoids dictionary
                        if self.cachedFactoids[state] == nil {
                            self.cachedFactoids[state] = []
                        }
                        self.cachedFactoids[state]?.append(fact)
                    }
                }
                
                print("✅ Preloaded \(fetchedRecords.count) factoids for offline use")
                
                // Save to UserDefaults for persistence
                self.saveCachedFactoids()
                self.lastFactoidFetchTime = Date()
                
                // DEBUG: Log factoid details
                self.logCachedFactoidStats()
                
            case .failure(let error):
                print("⚠️ Error preloading factoids: \(error.localizedDescription)")
                print("⚠️ CloudKit error details: \(String(describing: error))")
                print("⚠️ Network status during error: \(self.isNetworkAvailable ? "Available" : "Unavailable")")
                
                // Load from UserDefaults as fallback
                self.loadCachedFactoids()
            }
            
            self.isPreloadingFactoids = false
        }
        
        // DEBUG: Log operation details
        print("☁️ Creating CloudKit operation: \(operation)")
        
        publicDatabase.add(operation)
        
        // Immediately load cached factoids while waiting for fresh data
        loadCachedFactoids()
    }
    
    // DEBUG: Log statistics about cached factoids
    private func logCachedFactoidStats() {
        print("📊 FACTOID CACHE STATS:")
        print("📊 Total states with cached factoids: \(cachedFactoids.count)")
        
        var totalFactoids = 0
        var statesWithFactoids: [String] = []
        
        for (state, facts) in cachedFactoids {
            totalFactoids += facts.count
            print("📊 State \"\(state)\" has \(facts.count) factoids")
            if facts.count > 0 {
                statesWithFactoids.append(state)
            }
        }
        
        print("📊 Total factoids cached: \(totalFactoids)")
        print("📊 States with factoids: \(statesWithFactoids.joined(separator: ", "))")
        
        if let lastFetch = lastFactoidFetchTime {
            print("📊 Last factoid fetch time: \(lastFetch)")
        } else {
            print("📊 No previous factoid fetch recorded")
        }
    }
    
    private func saveCachedFactoids() {
        guard !cachedFactoids.isEmpty else { return }
        
        // Save to UserDefaults for offline access
        if let encodedData = try? JSONEncoder().encode(cachedFactoids) {
            UserDefaults.standard.set(encodedData, forKey: "CachedFactoids")
            print("💾 Saved \(cachedFactoids.count) state factoid categories to UserDefaults")
        }
    }
    
    private func loadCachedFactoids() {
        // Load previously cached factoids
        if let savedData = UserDefaults.standard.data(forKey: "CachedFactoids"),
           let loadedFactoids = try? JSONDecoder().decode([String: [String]].self, from: savedData) {
            // Merge with existing cached factoids
            for (state, facts) in loadedFactoids {
                if cachedFactoids[state] == nil {
                    cachedFactoids[state] = facts
                } else {
                    // Append unique facts
                    let existingFacts = Set(cachedFactoids[state] ?? [])
                    for fact in facts {
                        if !existingFacts.contains(fact) {
                            cachedFactoids[state]?.append(fact)
                        }
                    }
                }
            }
            print("📖 Loaded \(loadedFactoids.count) state factoid categories from UserDefaults")
            
            // DEBUG: Log what we loaded
            for (state, facts) in loadedFactoids {
                if !facts.isEmpty {
                    print("📖 Loaded \(facts.count) factoids for \(state)")
                }
            }
        }
    }
    
    // New prioritized factoid fetching method
    private func fetchFactoidWithPriority(for state: String, completion: @escaping (String?) -> Void) {
        print("🔍 Fetching factoid for state with priority: \(state)")
        
        // 1. First check if internet is available
        let isOnline = checkInternetConnection()
        print("🌐 Internet connection check: \(isOnline ? "Connected" : "Disconnected")")
        print("🌐 Network monitor says: \(isNetworkAvailable ? "Available" : "Unavailable")")
        
        // DEBUG: Log CloudKit container status
        checkCloudKitStatus()
        
        // 2. If online, try CloudKit first, fall back to cache if needed
        //    If offline, use cache directly
        if isOnline {
            // Try CloudKit first (with timeout)
            print("📡 Internet available - trying CloudKit fetch first")
            fetchFactoidFromCloudKit(for: state) { [weak self] (cloudResult) in
                guard let self = self else {
                    completion(nil)
                    return
                }
                
                if let factoid = cloudResult {
                    // Successfully fetched from CloudKit
                    print("☁️ Successfully fetched factoid from CloudKit")
                    self.factoidSourceStats["cloudKit"] = (self.factoidSourceStats["cloudKit"] ?? 0) + 1
                    completion(factoid)
                } else {
                    // CloudKit fetch failed, try cache
                    print("☁️ CloudKit fetch failed, falling back to cache")
                    self.fetchFactoidFromCache(for: state, completion: completion)
                }
            }
        } else {
            // Offline - use cache directly
            print("📡 No internet - using cached factoids")
            fetchFactoidFromCache(for: state, completion: completion)
        }
    }
    
    // DEBUG: Check CloudKit container status
    private func checkCloudKitStatus() {
        cloudContainer.accountStatus { status, error in
            var statusString: String
            
            switch status {
            case .available:
                statusString = "Available"
            case .noAccount:
                statusString = "No iCloud Account"
            case .restricted:
                statusString = "Restricted"
            case .couldNotDetermine:
                statusString = "Could Not Determine"
            default:
                statusString = "Unknown (\(status.rawValue))"
            }
            
            print("☁️ CloudKit container status: \(statusString)")
            if let error = error {
                print("☁️ CloudKit container error: \(error.localizedDescription)")
            }
        }
        
        // Check container configuration
        print("☁️ CloudKit container ID: \(String(describing: cloudContainer.containerIdentifier))")
        print("☁️ Using public database: \(publicDatabase)")
    }
    
    // Helper to check internet connection
    private func checkInternetConnection() -> Bool {
        // Use both methods - network path monitor and CloudKit status
        if isNetworkAvailable {
            return true
        }
        
        // Secondary method - check reachability to CloudKit
        let semaphore = DispatchSemaphore(value: 0)
        var isOnline = false
        
        cloudContainer.accountStatus { (accountStatus, error) in
            // If we can get the account status, we're likely online
            if error == nil {
                isOnline = true
            }
            semaphore.signal()
        }
        
        // Wait up to 1 second for the check
        _ = semaphore.wait(timeout: .now() + 1.0)
        
        return isOnline
    }
    
    // Fetch factoid from CloudKit with timeout
    private func fetchFactoidFromCloudKit(for state: String, completion: @escaping (String?) -> Void) {
        // Create a background task for this fetch
        let taskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endFactoidFetchTask(for: state)
        }
        
        factoidFetchTasks[state] = taskId
        
        // DEBUG: Extended timeout for testing
        let timeoutDuration: TimeInterval = 5.0 // 5 seconds instead of 3
        
        // Setup timeout - if fetch takes too long, fall back to cache
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            print("⏰ CloudKit fetch timed out after \(timeoutDuration) seconds")
            self?.endFactoidFetchTask(for: state)
            completion(nil)
        }
        
        // Schedule timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration, execute: timeoutWorkItem)
        
        // Create query for both state-specific and generic factoids
        let predicate = NSPredicate(format: "state IN %@", [state, "Generic"])
        let query = CKQuery(recordType: "StateFactoids", predicate: predicate)
        
        // DEBUG: Log query details
        print("☁️ CloudKit query: \(query)")
        print("☁️ CloudKit predicate: \(predicate)")
        
        let operation = CKQueryOperation(query: query)
        var fetchedRecords = [CKRecord]()
        
        operation.recordMatchedBlock = { (_, result) in
            switch result {
            case .success(let record):
                print("☁️ CloudKit found record: \(record.recordID.recordName)")
                fetchedRecords.append(record)
            case .failure(let error):
                print("⚠️ CloudKit record fetch failed: \(error.localizedDescription)")
                print("⚠️ CloudKit error details: \(String(describing: error))")
            }
        }
        
        operation.queryResultBlock = { [weak self] result in
            // Cancel the timeout
            timeoutWorkItem.cancel()
            
            guard let self = self else {
                completion(nil)
                return
            }
            
            switch result {
            case .success:
                print("☁️ CloudKit query completed successfully with \(fetchedRecords.count) records")
                
                // Group factoids by state
                var stateFactoids: [String: [String]] = [:]
                
                for record in fetchedRecords {
                    if let state = record["state"] as? String,
                       let fact = record["fact"] as? String {
                        // Fixed the optional string interpolation warning
                        print("☁️ CloudKit record details - State: \(String(describing: state)), Fact: \"\(String(describing: fact))\"")
                        
                        if stateFactoids[state] == nil {
                            stateFactoids[state] = []
                        }
                        stateFactoids[state]?.append(fact)
                    } else {
                        print("⚠️ CloudKit record missing state or fact fields: \(record)")
                        print("⚠️ Record keys: \(record.allKeys().map { String(describing: $0) })")
                    }
                }
                
                // Update our cache
                for (stateName, facts) in stateFactoids {
                    if self.cachedFactoids[stateName] == nil {
                        self.cachedFactoids[stateName] = facts
                    } else {
                        self.cachedFactoids[stateName]?.append(contentsOf: facts)
                    }
                }
                
                // Save updated cache
                self.saveCachedFactoids()
                
                // Now select the factoid to return
                var selectedFactoid: String? = nil
                
                if let stateSpecificFacts = stateFactoids[state], !stateSpecificFacts.isEmpty {
                    // Prefer state-specific factoids from CloudKit
                    selectedFactoid = stateSpecificFacts.randomElement()
                    print("☁️ Using state-specific factoid from CloudKit for \(state)")
                } else if let genericFacts = stateFactoids["Generic"], !genericFacts.isEmpty {
                    // Fall back to generic factoids from CloudKit
                    selectedFactoid = genericFacts.randomElement()
                    print("☁️ Using generic factoid from CloudKit")
                } else {
                    print("⚠️ CloudKit query succeeded but returned no usable factoids")
                }
                
                // End the background task
                self.endFactoidFetchTask(for: state)
                
                // Return the selected factoid
                completion(selectedFactoid)
                
            case .failure(let error):
                print("⚠️ CloudKit query failed: \(error.localizedDescription)")
                print("⚠️ CloudKit error details: \(String(describing: error))")
                print("⚠️ Network status during error: \(self.isNetworkAvailable ? "Available" : "Unavailable")")
                self.endFactoidFetchTask(for: state)
                completion(nil)
            }
        }
        
        print("☁️ Adding CloudKit operation to database")
        publicDatabase.add(operation)
    }
    
    // Fetch factoid from local cache
    private func fetchFactoidFromCache(for state: String, completion: @escaping (String?) -> Void) {
        // First try the cache for this specific state
        if let stateFactoids = cachedFactoids[state], !stateFactoids.isEmpty {
            let fact = stateFactoids.randomElement()!
            print("📖 Using cached factoid for \(state)")
            self.factoidSourceStats["stateCache"] = (self.factoidSourceStats["stateCache"] ?? 0) + 1
            completion(fact)
            return
        }
        
        // Next try cache for generic factoids
        if let genericFactoids = cachedFactoids["Generic"], !genericFactoids.isEmpty {
            let fact = genericFactoids.randomElement()!
            print("📖 Using generic cached factoid")
            self.factoidSourceStats["genericCache"] = (self.factoidSourceStats["genericCache"] ?? 0) + 1
            completion(fact)
            return
        }
        
        // Try offline fallbacks for this specific state
        if let stateFactoids = fallbackFactoids[state], !stateFactoids.isEmpty {
            let fact = stateFactoids.randomElement()!
            print("📖 Using offline fallback for \(state)")
            self.factoidSourceStats["fallback"] = (self.factoidSourceStats["fallback"] ?? 0) + 1
            completion(fact)
            return
        }
        
        // If we don't have state-specific factoids, use generic ones
        if let genericFactoids = fallbackFactoids["Generic"], !genericFactoids.isEmpty {
            let fact = genericFactoids.randomElement()!
            print("📖 Using generic factoid fallback")
            self.factoidSourceStats["fallback"] = (self.factoidSourceStats["fallback"] ?? 0) + 1
            completion(fact)
            return
        }
        
        // Last resort - use hardcoded welcome message
        completion("Welcome to \(state)! A new adventure begins!")
    }
    
    private func endFactoidFetchTask(for state: String) {
        if let taskID = factoidFetchTasks[state], taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
            factoidFetchTasks.removeValue(forKey: state)
        }
    }
}
