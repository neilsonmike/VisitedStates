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
    private let cooldownInterval: TimeInterval = 1 // 5 minutes
    private let cooldownKeyPrefix = "lastNotified_"
    private var notificationBackgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]
    private var cloudSyncComplete = false
    private var pendingStateDetections: [String] = []
    
    
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
    
    // Cached factoids to handle offline scenarios
    private var cachedFactoids: [String: [String]] = [:]
    private var isPreloadingFactoids = false
    private var factoidFetchTasks: [String: UIBackgroundTaskIdentifier] = [:]
    
    // Cache for tracking visited states before notification
    private var statesVisitedBeforeCurrentSession: Set<String> = []
    private var hasLoadedInitialStates = false
    
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
        clearBadgeCount()
        
        // Load initial states for proper "new state" detection
        loadInitialVisitedStates()
        
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
        
        // Make sure initial states are loaded
        if !hasLoadedInitialStates {
            loadInitialVisitedStates()
        }
        
        // Check if CloudKit sync is still in progress
        if !cloudSyncComplete && settings.visitedStates.value.isEmpty {
            print("⚠️ Deferring notification decision until cloud sync completes")
            // Store this state to process after sync completes
            pendingStateDetections.append(state)
            return
        }
        
        // Always notify for state changes, regardless of whether the state has been visited before
        // UNLESS the user has set notifyOnlyNewStates to true
        if shouldNotifyForState(state) {
            // Check if we should notify only for new states
            if settings.notifyOnlyNewStates.value {
                // Check if this state was visited BEFORE the current detection
                let isNewState = !statesVisitedBeforeCurrentSession.contains(state)
                
                print("🔍 DEBUG: Previously visited states: \(statesVisitedBeforeCurrentSession.sorted().joined(separator: ", "))")
                print("🔍 DEBUG: Is \(state) a new state? \(isNewState ? "YES" : "NO")")
                
                if isNewState {
                    print("🔔 Notification allowed for \(state) - not previously visited and notify only new states is enabled")
                    scheduleStateEntryNotification(for: state)
                    
                    // Add to our tracking set after notification decision
                    statesVisitedBeforeCurrentSession.insert(state)
                } else {
                    print("🔔 Skipping notification for already visited state: \(state) (notify only new states is enabled)")
                }
            } else {
                // Notify for all state changes
                print("🔔 Will notify for state: \(state)")
                scheduleStateEntryNotification(for: state)
            }
            
            // Always add to our session tracking
            statesVisitedBeforeCurrentSession.insert(state)
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
            
            // Schedule notification with time delay for better background delivery
            self.sendEnhancedNotification(for: state, fact: factoid)
            
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
    
    // Load visited states at initialization for proper "new state" detection
    private func loadInitialVisitedStates() {
        // Load all currently visited states to initialize our tracking set
        let initialStates = settings.visitedStates.value
        statesVisitedBeforeCurrentSession = Set(initialStates)
        
        // Also load any GPS-verified states to ensure comprehensive tracking
        let gpsVerifiedStates = settings.getAllGPSVerifiedStates()
        for state in gpsVerifiedStates {
            if state.wasEverVisited {
                statesVisitedBeforeCurrentSession.insert(state.stateName)
            }
        }
        
        hasLoadedInitialStates = true
        print("🔍 Loaded initial visited states for notification logic: \(statesVisitedBeforeCurrentSession.sorted().joined(separator: ", "))")
    }
    
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
    
    private func sendEnhancedNotification(for state: String, fact: String?) {
        print("🔔 Preparing enhanced notification for \(state)")
        
        let content = UNMutableNotificationContent()
        content.title = "Welcome to \(state)!"
        
        // Only set the body if we have a factoid, otherwise leave it with just the title
        if let factText = fact {
            content.body = factText
        }
        
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
    
    // MARK: - New factoid selection logic
    
    // Main method for prioritized factoid fetching
    private func fetchFactoidWithPriority(for state: String, completion: @escaping (String?) -> Void) {
        print("🔍 Fetching factoid for state with priority: \(state)")
        
        // Check if internet is available
        let isOnline = checkInternetConnection()
        
        if isOnline {
            // First priority: Try to get state-specific factoid from CloudKit
            fetchSpecificStateFactoidFromCloudKit(for: state) { [weak self] stateSpecificFactoid in
                guard let self = self else { return completion(nil) }
                
                if let factoid = stateSpecificFactoid {
                    // Success - we have a state-specific factoid from CloudKit
                    print("☁️ Successfully fetched state-specific factoid from CloudKit")
                    completion(factoid)
                    return
                }
                
                // Second priority: Try cached state-specific factoid
                if let cachedStateFactoid = self.getCachedFactoid(for: state) {
                    print("💾 Using cached state-specific factoid")
                    completion(cachedStateFactoid)
                    return
                }
                
                // Third priority: Try to get generic factoid from CloudKit
                self.fetchGenericFactoidFromCloudKit { genericFactoid in
                    if let factoid = genericFactoid {
                        // Success - we have a generic factoid from CloudKit
                        print("☁️ Successfully fetched generic factoid from CloudKit")
                        completion(factoid)
                        return
                    }
                    
                    // Fourth priority: Try cached generic factoid
                    if let cachedGenericFactoid = self.getCachedFactoid(for: "Generic") {
                        print("💾 Using cached generic factoid")
                        completion(cachedGenericFactoid)
                        return
                    }
                    
                    // No factoid available - just use nil for basic welcome message
                    print("ℹ️ No factoids available - using basic welcome message")
                    completion(nil)
                }
            }
        } else {
            // Offline mode - use cache only
            print("📡 No internet - trying cached factoids")
            
            // First try state-specific cache
            if let cachedStateFactoid = getCachedFactoid(for: state) {
                print("💾 Using cached state-specific factoid")
                completion(cachedStateFactoid)
                return
            }
            
            // Then try generic cache
            if let cachedGenericFactoid = getCachedFactoid(for: "Generic") {
                print("💾 Using cached generic factoid")
                completion(cachedGenericFactoid)
                return
            }
            
            // No factoid available - just use nil for basic welcome message
            print("ℹ️ No factoids available - using basic welcome message")
            completion(nil)
        }
    }
    
    // Helper to get a cached factoid from memory
    private func getCachedFactoid(for state: String) -> String? {
        // Check if we have cached factoids for this state
        if let stateFactoids = cachedFactoids[state], !stateFactoids.isEmpty {
            return stateFactoids.randomElement()
        }
        return nil
    }
    
    // Fetch specifically state-related factoids from CloudKit
    private func fetchSpecificStateFactoidFromCloudKit(for state: String, completion: @escaping (String?) -> Void) {
        // Create a background task for this fetch
        let taskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endFactoidFetchTask(for: state)
        }
        
        factoidFetchTasks[state] = taskId
        
        // Setup timeout - if fetch takes too long, fall back to next option
        let timeoutDuration: TimeInterval = 5.0
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            print("⏰ CloudKit fetch timed out after \(timeoutDuration) seconds")
            self?.endFactoidFetchTask(for: state)
            completion(nil)
        }
        
        // Schedule timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration, execute: timeoutWorkItem)
        
        // Create query for state-specific factoids only
        let predicate = NSPredicate(format: "state == %@", state)
        let query = CKQuery(recordType: "StateFactoids", predicate: predicate)
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 10 // Limit to avoid excessive network usage
        var fetchedFactoids: [String] = []
        
        operation.recordMatchedBlock = { (_, result) in
            switch result {
            case .success(let record):
                if let fact = record["fact"] as? String {
                    fetchedFactoids.append(fact)
                }
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
                // Update cache with any fetched factoids
                if !fetchedFactoids.isEmpty {
                    // Update the cache
                    if self.cachedFactoids[state] == nil {
                        self.cachedFactoids[state] = []
                    }
                    
                    // Add any new factoids to the cache
                    for fact in fetchedFactoids {
                        if !(self.cachedFactoids[state]?.contains(fact) ?? false) {
                            self.cachedFactoids[state]?.append(fact)
                        }
                    }
                    
                    // Save updated cache
                    self.saveCachedFactoids()
                    
                    // Return a random factoid from the results
                    let selectedFactoid = fetchedFactoids.randomElement()
                    
                    // End the background task
                    self.endFactoidFetchTask(for: state)
                    
                    // Return the selected factoid
                    completion(selectedFactoid)
                } else {
                    // No factoids found for this state
                    self.endFactoidFetchTask(for: state)
                    completion(nil)
                }
                
            case .failure(let error):
                print("⚠️ Error fetching state factoids: \(error.localizedDescription)")
                self.endFactoidFetchTask(for: state)
                completion(nil)
            }
        }
        
        publicDatabase.add(operation)
    }
    
    // Fetch generic factoids from CloudKit
    private func fetchGenericFactoidFromCloudKit(completion: @escaping (String?) -> Void) {
        // Create query for generic factoids only
        let predicate = NSPredicate(format: "state == %@", "Generic")
        let query = CKQuery(recordType: "StateFactoids", predicate: predicate)
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 10 // Limit to avoid excessive network usage
        var fetchedFactoids: [String] = []
        
        operation.recordMatchedBlock = { (_, result) in
            switch result {
            case .success(let record):
                if let fact = record["fact"] as? String {
                    fetchedFactoids.append(fact)
                }
            case .failure:
                // Error handling in queryResultBlock
                break
            }
        }
        
        operation.queryResultBlock = { [weak self] result in
            guard let self = self else {
                completion(nil)
                return
            }
            
            switch result {
            case .success:
                // Update cache with any fetched factoids
                if !fetchedFactoids.isEmpty {
                    // Update the cache
                    if self.cachedFactoids["Generic"] == nil {
                        self.cachedFactoids["Generic"] = []
                    }
                    
                    // Add any new factoids to the cache
                    for fact in fetchedFactoids {
                        if !(self.cachedFactoids["Generic"]?.contains(fact) ?? false) {
                            self.cachedFactoids["Generic"]?.append(fact)
                        }
                    }
                    
                    // Save updated cache
                    self.saveCachedFactoids()
                    
                    // Return a random factoid from the results
                    let selectedFactoid = fetchedFactoids.randomElement()
                    completion(selectedFactoid)
                } else {
                    // No generic factoids found
                    completion(nil)
                }
                
            case .failure(let error):
                print("⚠️ Error fetching generic factoids: \(error.localizedDescription)")
                completion(nil)
            }
        }
        
        publicDatabase.add(operation)
    }
    
    private func endFactoidFetchTask(for state: String) {
        if let taskID = factoidFetchTasks[state], taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
            factoidFetchTasks.removeValue(forKey: state)
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
    
    // MARK: - Cloud Sync Integration

    /// Call this when cloud sync completes to process pending notifications
    func cloudSyncDidComplete() {
        cloudSyncComplete = true
        print("☁️ Cloud sync completed - processing \(pendingStateDetections.count) pending state detections")
        
        // Process any pending state detections
        for state in pendingStateDetections {
            handleDetectedState(state)
        }
        pendingStateDetections.removeAll()
    }
}
