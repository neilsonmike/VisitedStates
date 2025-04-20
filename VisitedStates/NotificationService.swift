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
        
        // Check the current notification authorization status
        checkNotificationAuthorization()
        
        // Register notification categories and actions
        registerNotificationCategories()
        
        // Preload factoids for offline use
        preloadFactoids()
        
        // Clear any existing badges
        // FIXED: Replace deprecated applicationIconBadgeNumber with UNUserNotificationCenter
        clearBadgeCount()
        
        print("🔔 NotificationService initialized")
    }
    
    deinit {
        networkMonitor?.cancel()
    }
    
    // MARK: - NotificationServiceProtocol
    
    func requestNotificationPermissions() {
        print("🔔 EXPLICITLY requesting notification permissions...")
        
        // Important: Use standard notification options, but REMOVE badge option
        let options: UNAuthorizationOptions = [.alert, .sound]
        
        // Use the main thread for the permission request
        DispatchQueue.main.async {
            self.userNotificationCenter.requestAuthorization(options: options) { [weak self] granted, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("⚠️ Notification permission error: \(error.localizedDescription)")
                }
                
                // Update authorization status - this triggers the Combine publisher
                // which the app uses to sequence the next permission request
                DispatchQueue.main.async {
                    if granted {
                        print("✅ Notification permission GRANTED")
                    } else {
                        print("⚠️ Notification permission DENIED")
                    }
                    
                    // Clear any badges
                    self.clearBadgeCount()
                    
                    // This is the critical line that signals permission response
                    self.isNotificationsAuthorized.send(granted)
                }
            }
        }
    }
    
    func handleDetectedState(_ state: String) {
        print("🔔 Handling detection of state: \(state)")
        
        // Always notify for state changes, regardless of whether the state has been visited before
        // UNLESS the user has set notifyOnlyNewStates to true
        if shouldNotifyForState(state) {
            // Check if we should notify only for new states
            if settings.notifyOnlyNewStates.value {
                // Check if this state has been visited before
                if !settings.hasVisitedState(state) {
                    print("🔔 Will notify for new state: \(state)")
                    scheduleStateEntryNotification(for: state)
                } else {
                    print("🔔 Skipping notification for already visited state: \(state) (notify only new states is enabled)")
                }
            } else {
                // Notify for all state changes
                print("🔔 Will notify for state: \(state)")
                scheduleStateEntryNotification(for: state)
            }
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
        
        // Fetch factoid with priority on CloudKit and fall back to cache
        fetchFactoidWithPriority(for: state) { [weak self] factoid in
            guard let self = self else {
                UIApplication.shared.endBackgroundTask(bgTask)
                return
            }
            
            // Use the factoid or a default welcome message
            let factText = factoid ?? "Welcome to \(state)!"
            
            // Schedule notification with time delay for better background delivery
            self.sendEnhancedNotification(for: state, fact: factText)
            
            // Update tracking
            UserDefaults.standard.set(Date(), forKey: key)
            
            // Update the persistent last notified state
            self.lastNotifiedState = state
            print("🔔 Updated persistent last notified state to: \(state)")
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Present notifications even when app is in foreground but DO NOT include badge
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .list])
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
        // Clear badge when user interacts with notification
        clearBadgeCount()
        completionHandler()
    }
    
    // MARK: - Private methods
    
    // FIXED: Add a new method to handle badge count in a modern way
    private func clearBadgeCount() {
        if #available(iOS 17.0, *) {
            // Use the new API for iOS 17+
            userNotificationCenter.setBadgeCount(0) { error in
                if let error = error {
                    print("⚠️ Error clearing badge count: \(error.localizedDescription)")
                }
            }
        } else {
            // Fall back to the old method for earlier iOS versions
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
    
    // FIXED: Add a method to set badge count
    private func setBadgeCount(_ count: Int) {
        if #available(iOS 17.0, *) {
            // Use the new API for iOS 17+
            userNotificationCenter.setBadgeCount(count) { error in
                if let error = error {
                    print("⚠️ Error setting badge count: \(error.localizedDescription)")
                }
            }
        } else {
            // Fall back to the old method for earlier iOS versions
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
    
    private func checkNotificationAuthorization() {
        userNotificationCenter.getNotificationSettings { [weak self] settings in
            let isAuthorized = settings.authorizationStatus == .authorized ||
                               settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                self?.isNotificationsAuthorized.send(isAuthorized)
                print("🔔 Initial notification authorization status: \(isAuthorized)")
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
            options: [.customDismissAction]  // Added custom dismiss action
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
        
        // FIXED: Set badge to 0 in notification content
        content.badge = 0
        
        // Add time-sensitive notification settings for better background delivery
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        
        // Add the state as a category identifier for potential actions
        content.categoryIdentifier = "STATE_ENTRY"
        
        // Add custom data for handling
        content.userInfo = ["state": state]
        
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
                
            case .failure(let error):
                print("⚠️ Error preloading factoids: \(error.localizedDescription)")
                
                // Load from UserDefaults as fallback
                self.loadCachedFactoids()
            }
            
            self.isPreloadingFactoids = false
        }
        
        publicDatabase.add(operation)
        
        // Immediately load cached factoids while waiting for fresh data
        loadCachedFactoids()
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
        }
    }
    
    // New prioritized factoid fetching method
    private func fetchFactoidWithPriority(for state: String, completion: @escaping (String?) -> Void) {
        print("🔍 Fetching factoid for state with priority: \(state)")
        
        // 1. First check if internet is available
        let isOnline = checkInternetConnection()
        
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
    
    // Helper to check internet connection
    private func checkInternetConnection() -> Bool {
        // Use network path monitor
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
    }
    
    // Fetch factoid from CloudKit with timeout
    private func fetchFactoidFromCloudKit(for state: String, completion: @escaping (String?) -> Void) {
        // Create a background task for this fetch
        let taskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endFactoidFetchTask(for: state)
        }
        
        factoidFetchTasks[state] = taskId
        
        // Setup timeout - if fetch takes too long, fall back to cache
        let timeoutDuration: TimeInterval = 5.0
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
        
        let operation = CKQueryOperation(query: query)
        var fetchedRecords = [CKRecord]()
        
        operation.recordMatchedBlock = { (_, result) in
            switch result {
            case .success(let record):
                fetchedRecords.append(record)
            case .failure:
                // Error handling in queryResultBlock
                break
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
                // Group factoids by state
                var stateFactoids: [String: [String]] = [:]
                
                for record in fetchedRecords {
                    if let state = record["state"] as? String,
                       let fact = record["fact"] as? String {
                        if stateFactoids[state] == nil {
                            stateFactoids[state] = []
                        }
                        stateFactoids[state]?.append(fact)
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
                } else if let genericFacts = stateFactoids["Generic"], !genericFacts.isEmpty {
                    // Fall back to generic factoids from CloudKit
                    selectedFactoid = genericFacts.randomElement()
                }
                
                // End the background task
                self.endFactoidFetchTask(for: state)
                
                // Return the selected factoid
                completion(selectedFactoid)
                
            case .failure:
                self.endFactoidFetchTask(for: state)
                completion(nil)
            }
        }
        
        publicDatabase.add(operation)
    }
    
    // Fetch factoid from local cache
    private func fetchFactoidFromCache(for state: String, completion: @escaping (String?) -> Void) {
        // First try the cache for this specific state
        if let stateFactoids = cachedFactoids[state], !stateFactoids.isEmpty {
            let fact = stateFactoids.randomElement()!
            self.factoidSourceStats["stateCache"] = (self.factoidSourceStats["stateCache"] ?? 0) + 1
            completion(fact)
            return
        }
        
        // Next try cache for generic factoids
        if let genericFactoids = cachedFactoids["Generic"], !genericFactoids.isEmpty {
            let fact = genericFactoids.randomElement()!
            self.factoidSourceStats["genericCache"] = (self.factoidSourceStats["genericCache"] ?? 0) + 1
            completion(fact)
            return
        }
        
        // Try offline fallbacks for this specific state
        if let stateFactoids = fallbackFactoids[state], !stateFactoids.isEmpty {
            let fact = stateFactoids.randomElement()!
            self.factoidSourceStats["fallback"] = (self.factoidSourceStats["fallback"] ?? 0) + 1
            completion(fact)
            return
        }
        
        // If we don't have state-specific factoids, use generic ones
        if let genericFactoids = fallbackFactoids["Generic"], !genericFactoids.isEmpty {
            let fact = genericFactoids.randomElement()!
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
    
    // Setup network monitoring
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
    }
}
