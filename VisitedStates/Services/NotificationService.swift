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
    // We've removed the cooldown-based approach in favor of direct state matching
    // These variables are kept but no longer used
    private var notificationCooldowns: [String: Date] = [:]
    private let cooldownKeyPrefix = "lastNotified_"
    // Define this for compilation purposes even though we're no longer using it
    private let cooldownInterval: TimeInterval = 1
    private var notificationBackgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]
    private var cloudSyncComplete = false
    private var pendingStateDetections: [String] = []
    
    // CloudKit retry configuration
    private let maxCloudKitRetries = 2
    private var cloudKitRetryCount = 0
    
    // DEBUG: Enhanced debugger flags
    private let debugFactoids = true  // Set to true to enable factoid debugging
    private let debugCloudKit = true  // Set to true to enable CloudKit debugging
    
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
    
    // DEBUG: Additional tracking for factoid operations
    private var factoidOriginLog: [String: String] = [:]  // Tracks where each factoid came from
    private var cloudKitRequestLog: [Date: (query: String, result: String)] = [:]  // Logs CloudKit requests
    private var factoidFetchAttempts = 0
    private var factoidFetchSuccesses = 0
    
    // Flag to check if we've created default factoids (to avoid using them when avoidable)
    private var usedDefaultFactoids = false
    
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
        
        // Clear existing factoid cache on startup (to prioritize fresh fetches)
        clearFactoidCache()
        
        // Load initial states for proper "new state" detection
        loadInitialVisitedStates()
        
        // Clear any existing badges
        clearBadgeCount()
        
        // DEBUG: Log initialization
        logDebug("🔔 NotificationService initialized with container: \(containerIdentifier)")
        
        // Verify CloudKit container configuration
        verifyCloudKitConfiguration()
        
        // Load cached factoids from UserDefaults (only needed for offline scenarios)
        loadCachedFactoids()
        
        logDebug("📚 Initial factoid cache state - Entries: \(self.cachedFactoids.count), States: \(self.cachedFactoids.keys.joined(separator: ", "))")
        
        // Preload factoids for offline use - call this last to ensure it starts right away
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.preloadFactoids(forceRefresh: true)
        }
        
        // Set up app state observer
        setupAppStateObserver()
    }
    
    deinit {
        networkMonitor?.cancel()
        NotificationCenter.default.removeObserver(self)
        logDebug("🚫 NotificationService deinit")
    }
    
    // MARK: - NotificationServiceProtocol
    
    func requestNotificationPermissions() {
        logDebug("🔔 EXPLICITLY requesting notification permissions...")
        
        // Important: Use standard notification options, but REMOVE badge option
        let options: UNAuthorizationOptions = [.alert, .sound]
        
        // Use the main thread for the permission request
        DispatchQueue.main.async {
            self.userNotificationCenter.requestAuthorization(options: options) { [weak self] granted, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logDebug("⚠️ Notification permission error: \(error.localizedDescription)")
                }
                
                // Update authorization status - this triggers the Combine publisher
                // which the app uses to sequence the next permission request
                DispatchQueue.main.async {
                    if granted {
                        self.logDebug("✅ Notification permission GRANTED")
                    } else {
                        self.logDebug("⚠️ Notification permission DENIED")
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
        logDebug("🔔 Handling detection of state: \(state)")
        
        // Make sure initial states are loaded
        if !hasLoadedInitialStates {
            loadInitialVisitedStates()
        }
        
        // Check if CloudKit sync is still in progress
        if !cloudSyncComplete && settings.visitedStates.value.isEmpty {
            logDebug("⚠️ Deferring notification decision until cloud sync completes")
            // Store this state to process after sync completes
            pendingStateDetections.append(state)
            return
        }
        
        // CRITICAL FIX: Check if app just became active AND this is the last notified state
        let didJustBecomeActive = UserDefaults.standard.bool(forKey: "didJustBecomeActive")
        let lastNotifiedState = UserDefaults.standard.string(forKey: "lastNotifiedState")
        
        if didJustBecomeActive && lastNotifiedState == state {
            logDebug("⚠️ DUPLICATE NOTIFICATION PREVENTED: App just became active and detected state \(state) matches last notified state")
            logDebug("🔕 Suppressing duplicate notification for \(state)")
            
            // Still update tracking
            statesVisitedBeforeCurrentSession.insert(state)
            return
        }
        
        // Check if we should notify for this state
        if state == lastNotifiedState {
            logDebug("🔔 Skip notification - matches last notified state: \(state)")
            statesVisitedBeforeCurrentSession.insert(state)
            return
        }
        
        // Always notify for state changes, regardless of whether the state has been visited before
        // UNLESS the user has set notifyOnlyNewStates to true
        if settings.notifyOnlyNewStates.value {
            // Check if this state was visited BEFORE the current detection
            let isNewState = !statesVisitedBeforeCurrentSession.contains(state)
            
            logDebug("🔍 DEBUG: Previously visited states: \(statesVisitedBeforeCurrentSession.sorted().joined(separator: ", "))")
            logDebug("🔍 DEBUG: Is \(state) a new state? \(isNewState ? "YES" : "NO")")
            
            if isNewState {
                logDebug("🔔 Notification allowed for \(state) - not previously visited and notify only new states is enabled")
                scheduleStateEntryNotification(for: state)
                
                // Add to our tracking set after notification decision
                statesVisitedBeforeCurrentSession.insert(state)
            } else {
                logDebug("🔔 Skipping notification for already visited state: \(state) (notify only new states is enabled)")
                statesVisitedBeforeCurrentSession.insert(state)
            }
        } else {
            // Notify for all state changes
            logDebug("🔔 Will notify for state: \(state)")
            scheduleStateEntryNotification(for: state)
            statesVisitedBeforeCurrentSession.insert(state)
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
            logDebug("🔔 Notifications are disabled in settings. Skipping.")
            endBackgroundTask(for: state)
            return
        }
        
        // Skip if same as last notified (to prevent duplicates)
        if state == lastNotifiedState {
            logDebug("🔔 \(state) was just notified. Preventing duplicate.")
            endBackgroundTask(for: state)
            return
        }
        
        // We no longer use cooldown-based approach, but we'll record when this state was last notified
        // for debugging purposes
        let key = cooldownKeyPrefix + state
        UserDefaults.standard.set(Date(), forKey: key)
        
        logDebug("🔔 Starting notification process for \(state)")
        
        // DEBUG: Log the factoid cache state before fetching
        logDebug("📚 Factoid cache state before fetch - Entries: \(cachedFactoids.count), States with factoids: \(cachedFactoids.keys.joined(separator: ", "))")
        if cachedFactoids[state] != nil {
            logDebug("📚 Found \(cachedFactoids[state]!.count) cached factoids for \(state)")
            
            // Log the actual factoids for debugging
            for (index, factoid) in cachedFactoids[state]!.enumerated() {
                logDebug("📚 Cached factoid [\(index)]: \(factoid)")
            }
        } else {
            logDebug("📚 No cached factoids found for \(state)")
        }
        
        // Reset tracking for this factoid fetch
        factoidOriginLog[state] = "unknown"
        factoidFetchAttempts += 1
        
        // Fetch factoid with network priority
        fetchFactoidWithNetworkPriority(for: state) { [weak self] factoid in
            guard let self = self else {
                UIApplication.shared.endBackgroundTask(bgTask)
                return
            }
            
            // DEBUG: Log the factoid source
            if let factoid = factoid, let source = self.factoidOriginLog[state] {
                self.logDebug("📚 Using factoid from source: \(source)")
                self.logDebug("📚 Factoid content: \(factoid)")
            } else {
                self.logDebug("📚 No factoid available for notification")
            }
            
            // Schedule notification with time delay for better background delivery
            self.sendEnhancedNotification(for: state, fact: factoid)
            
            // Update tracking
            UserDefaults.standard.set(Date(), forKey: key)
            
            // Update the persistent last notified state
            self.lastNotifiedState = state
            self.logDebug("🔔 Updated persistent last notified state to: \(state)")
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
    
    // Set up app state observer
    private func setupAppStateObserver() {
        // Add notification observer for when app becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Add notification observer for when app enters background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        // Explicitly refresh our cached view of the last notification state
        let lastNotifiedState = UserDefaults.standard.string(forKey: "lastNotifiedState")
        logDebug("🔔 App became active - last notified state: \(lastNotifiedState ?? "none")")
        
        // Set a flag indicating the app just became active
        // We'll use this flag to prevent duplicate notifications when app comes to foreground
        UserDefaults.standard.set(true, forKey: "didJustBecomeActive")
        UserDefaults.standard.synchronize()
        
        // Schedule removal of the flag after a short period
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UserDefaults.standard.removeObject(forKey: "didJustBecomeActive")
            UserDefaults.standard.synchronize()
            self.logDebug("🔔 Cleared app activation flag")
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Ensure UserDefaults are synchronized when app enters background
        UserDefaults.standard.synchronize()
        
        // Log the current lastNotifiedState
        let currentLastNotified = UserDefaults.standard.string(forKey: "lastNotifiedState")
        logDebug("🔔 App entered background - last notified state: \(currentLastNotified ?? "none")")
    }
    
    // Clear the factoid cache to force fresh fetches
    private func clearFactoidCache() {
        logDebug("🧹 Clearing factoid cache to prioritize fresh factoids")
        cachedFactoids.removeAll()
        UserDefaults.standard.removeObject(forKey: "CachedFactoids")
        UserDefaults.standard.removeObject(forKey: "lastFactoidFetchTime")
    }
    
    // DEBUG: Enhanced logging method
    private func logDebug(_ message: String) {
        // Always print important operational logs
        print(message)
        
        // Add to app group or file log if needed for persistent debugging
        // This would allow retrieving logs from the device later
        // Code for file logging would go here if needed
    }
    
    // DEBUG: Verify CloudKit container configuration
    private func verifyCloudKitConfiguration() {
        // Check if we can access the CloudKit container
        cloudContainer.accountStatus { [weak self] (accountStatus, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.logDebug("⚠️ CloudKit container error: \(error.localizedDescription)")
                return
            }
            
            switch accountStatus {
            case .available:
                self.logDebug("✅ CloudKit account is available")
                // Try to ping the database to verify further
                self.pingCloudKitDatabase()
            case .noAccount:
                self.logDebug("⚠️ CloudKit error: No iCloud account available")
            case .restricted:
                self.logDebug("⚠️ CloudKit error: iCloud account is restricted")
            case .couldNotDetermine:
                self.logDebug("⚠️ CloudKit error: Could not determine account status")
            case .temporarilyUnavailable:
                self.logDebug("⚠️ CloudKit error: iCloud account is temporarily unavailable")
            @unknown default:
                self.logDebug("⚠️ CloudKit error: Unknown account status")
            }
        }
    }
    
    // DEBUG: Ping CloudKit database to verify connectivity
    private func pingCloudKitDatabase() {
        // Create a simple query to check if we can reach the database
        let query = CKQuery(recordType: "StateFactoids", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1
        
        operation.recordMatchedBlock = { [weak self] (_, result) in
            switch result {
            case .success(let record):
                self?.logDebug("✅ Successfully pinged CloudKit database and received a record of type: \(record.recordType)")
                if let state = record["state"] as? String, let fact = record["fact"] as? String {
                    self?.logDebug("✅ Sample record - State: \(state), Fact: \(fact)")
                }
            case .failure(let error):
                self?.logDebug("⚠️ Record fetch failed during ping: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.logDebug("✅ CloudKit database ping operation completed successfully")
            case .failure(let error):
                self?.logDebug("⚠️ CloudKit database ping operation failed: \(error.localizedDescription)")
            }
        }
        
        // Execute the operation
        publicDatabase.add(operation)
    }
    
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
        logDebug("🔍 Loaded initial visited states for notification logic: \(statesVisitedBeforeCurrentSession.sorted().joined(separator: ", "))")
    }
    
    // FIXED: Add a new method to handle badge count in a modern way
    private func clearBadgeCount() {
        if #available(iOS 17.0, *) {
            // Use the new API for iOS 17+
            userNotificationCenter.setBadgeCount(0) { error in
                if let error = error {
                    self.logDebug("⚠️ Error clearing badge count: \(error.localizedDescription)")
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
                    self.logDebug("⚠️ Error setting badge count: \(error.localizedDescription)")
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
                self?.logDebug("🔔 Initial notification authorization status: \(isAuthorized)")
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
    
    // We've removed this method entirely since we now handle the logic directly in handleDetectedState
    // This is just a placeholder to satisfy Swift compilation - it's no longer used
    private func shouldNotifyForState(_ state: String) -> Bool {
        // This method has been replaced with direct logic in handleDetectedState
        return true
    }
    
    private func sendEnhancedNotification(for state: String, fact: String?) {
        logDebug("🔔 Preparing enhanced notification for \(state)")
        
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
                self?.logDebug("⚠️ Error scheduling notification for \(state): \(error.localizedDescription)")
            } else {
                self?.logDebug("✅ Notification scheduled for \(state)")
            }
            
            // End the background task
            self?.endBackgroundTask(for: state)
        }
    }
    
    private func endBackgroundTask(for state: String) {
        if let taskID = notificationBackgroundTasks[state], taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
            notificationBackgroundTasks.removeValue(forKey: state)
            logDebug("🔔 Ended background task for notification: \(state)")
        }
    }
    
    // IMPROVED: Enhanced preloadFactoids with force refresh option and completion handler
    private func preloadFactoids(forceRefresh: Bool = false, completion: (() -> Void)? = nil) {
        // Avoid multiple concurrent preloads
        guard !isPreloadingFactoids else {
            logDebug("📚 Factoid preload already in progress, skipping")
            completion?()
            return
        }
        
        // First try to load any existing cached factoids
        loadCachedFactoids()
        
        // Check if we already have cache and don't need to refresh
        if !forceRefresh && !cachedFactoids.isEmpty {
            if let lastFetch = lastFactoidFetchTime,
               Date().timeIntervalSince(lastFetch) < factoidCacheAge {
                // If the cache is less than a week old and not empty, we can use it
                logDebug("📚 Using existing factoid cache (age: \(Int(Date().timeIntervalSince(lastFetch)/3600))h)")
                completion?()
                return
            }
        }
        
        isPreloadingFactoids = true
        
        logDebug("📚 Preloading state factoids for all states...")
        
        // Create query for all factoids
        let query = CKQuery(recordType: "StateFactoids", predicate: NSPredicate(value: true))
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 100 // Get a good batch
        
        var fetchedRecords = [CKRecord]()
        
        // DEBUG: Log the CloudKit query
        let queryTime = Date()
        cloudKitRequestLog[queryTime] = (query: "StateFactoids with NSPredicate(value: true)", result: "pending")
        
        operation.recordMatchedBlock = { [weak self] (_, result) in
            switch result {
            case .success(let record):
                fetchedRecords.append(record)
                if let state = record["state"] as? String, let fact = record["fact"] as? String {
                    self?.logDebug("📄 Received record - State: \(state), Fact: \(fact.prefix(30))...")
                }
            case .failure(let error):
                self?.logDebug("⚠️ Record fetch failed: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            
            switch result {
            case .success:
                // Update CloudKit request log
                self.cloudKitRequestLog[queryTime] = (
                    query: "StateFactoids with NSPredicate(value: true)",
                    result: "success: \(fetchedRecords.count) records")
                
                // Process the fetched records
                var newFactoids: [String: [String]] = [:]
                var fetchSummary: [String: Int] = [:]
                
                for record in fetchedRecords {
                    if let state = record["state"] as? String,
                       let fact = record["fact"] as? String {
                        // Add to new factoids dictionary
                        if newFactoids[state] == nil {
                            newFactoids[state] = []
                            fetchSummary[state] = 0
                        }
                        newFactoids[state]?.append(fact)
                        fetchSummary[state] = (fetchSummary[state] ?? 0) + 1
                    }
                }
                
                // Log summary of what we fetched
                self.logDebug("📚 CloudKit fetch summary:")
                for (state, count) in fetchSummary {
                    self.logDebug("  - \(state): \(count) factoids")
                }
                
                if fetchedRecords.isEmpty {
                    self.logDebug("⚠️ No factoids found in CloudKit, this is unusual")
                }
                
                // If we got records from CloudKit, clear any existing cache first
                if !fetchedRecords.isEmpty {
                    self.cachedFactoids.removeAll()
                }
                
                // Now add the fresh factoids to the cache
                for (state, facts) in newFactoids {
                    self.cachedFactoids[state] = facts
                }
                
                self.logDebug("✅ Preloaded \(fetchedRecords.count) factoids for offline use")
                
                // Save to UserDefaults for persistence
                self.saveCachedFactoids()
                self.lastFactoidFetchTime = Date()
                
                // Only create fallback factoids if we got nothing from CloudKit
                if fetchedRecords.isEmpty {
                    self.logDebug("❌ CloudKit returned no factoids, creating fallbacks")
                    self.createFallbackFactoids()
                }
                
                // Increment success counter
                self.factoidFetchSuccesses += 1
                
            case .failure(let error):
                // Update CloudKit request log
                self.cloudKitRequestLog[queryTime] = (
                    query: "StateFactoids with NSPredicate(value: true)",
                    result: "failure: \(error.localizedDescription)")
                
                self.logDebug("⚠️ Error preloading factoids: \(error.localizedDescription)")
                
                // DEBUG: Add error details
                if let ckError = error as? CKError {
                    self.logDebug("⚠️ CloudKit error code: \(ckError.code.rawValue)")
                    if let serverRecord = ckError.serverRecord {
                        self.logDebug("⚠️ Server record returned: \(serverRecord.recordType)")
                    }
                    if let retryAfter = ckError.retryAfterSeconds {
                        self.logDebug("⚠️ Retry suggested after: \(retryAfter) seconds")
                    }
                }
                
                // Keep using any existing loaded factoids
                if self.cachedFactoids.isEmpty {
                    self.logDebug("📚 Creating fallback factoids since cache is empty")
                    self.createFallbackFactoids()
                }
            }
            
            self.isPreloadingFactoids = false
            completion?()
        }
        
        publicDatabase.add(operation)
    }
    
    // Create minimal fallback factoids for offline use
    private func createFallbackFactoids() {
        logDebug("📚 Creating minimal fallback factoids for offline use")
        
        // Flag that we're using default factoids
        usedDefaultFactoids = true
        
        // Create just one generic factoid
        cachedFactoids["Generic"] = [
            "You've entered a new state!"
        ]
        
        // Save the fallback factoids
        saveCachedFactoids()
    }
    
    private func saveCachedFactoids() {
        guard !cachedFactoids.isEmpty else { return }
        
        // Save to UserDefaults for offline access
        if let encodedData = try? JSONEncoder().encode(cachedFactoids) {
            UserDefaults.standard.set(encodedData, forKey: "CachedFactoids")
            logDebug("💾 Saved \(cachedFactoids.count) state factoid categories to UserDefaults")
            
            // DEBUG: Log summary of what's in the cache
            var cacheSummary = ""
            for (state, facts) in cachedFactoids {
                cacheSummary += "\(state): \(facts.count) factoids, "
            }
            logDebug("💾 Cache contents: \(cacheSummary)")
        } else {
            logDebug("⚠️ Failed to encode factoids for UserDefaults")
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
            logDebug("📖 Loaded \(loadedFactoids.count) state factoid categories from UserDefaults")
            
            // DEBUG: Log what was loaded from cache
            var cacheSummary = ""
            for (state, facts) in loadedFactoids {
                cacheSummary += "\(state): \(facts.count) factoids, "
            }
            logDebug("📖 Loaded cache contents: \(cacheSummary)")
        } else {
            logDebug("📖 No factoid cache found in UserDefaults")
        }
    }
    
    // MARK: - New factoid selection logic
    
    // NEW: Network-first factoid fetching strategy
    private func fetchFactoidWithNetworkPriority(for state: String, completion: @escaping (String?) -> Void) {
        logDebug("🔍 Fetching factoid with NETWORK PRIORITY for state: \(state)")
        
        // Check if internet is available
        let isOnline = checkInternetConnection()
        logDebug("🌐 Network status: \(isOnline ? "Online" : "Offline")")
        
        if isOnline {
            // Try to get state-specific factoid from CloudKit
            let timeoutDuration: TimeInterval = 6.0
            
            logDebug("☁️ Attempting CloudKit fetch for state: \(state) with \(timeoutDuration)s timeout")
            
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.logDebug("⏰ CloudKit fetch timed out after \(timeoutDuration)s, falling back to cache")
                
                // Try cached state-specific factoid first
                if let cachedStateFactoid = self?.getCachedFactoid(for: state) {
                    self?.logDebug("💾 Using cached state-specific factoid after timeout")
                    self?.factoidOriginLog[state] = "cache_state_specific_after_timeout"
                    completion(cachedStateFactoid)
                    return
                }
                
                // Try cached generic factoid
                if let cachedGenericFactoid = self?.getCachedFactoid(for: "Generic") {
                    self?.logDebug("💾 Using cached generic factoid after timeout")
                    self?.factoidOriginLog[state] = "cache_generic_after_timeout"
                    completion(cachedGenericFactoid)
                    return
                }
                
                // Last resort - basic message
                self?.logDebug("💬 Using basic welcome message after timeout")
                self?.factoidOriginLog[state] = "basic_message_after_timeout"
                completion("You've entered a new state!")
            }
            
            // Set a timeout timer
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration, execute: timeoutWorkItem)
            
            // Start the CloudKit fetch
            fetchSpecificStateFactoidFromCloudKit(for: state) { [weak self] stateSpecificFactoid in
                // Cancel the timeout
                timeoutWorkItem.cancel()
                
                guard let self = self else { return completion(nil) }
                
                if let factoid = stateSpecificFactoid {
                    // Success - we have a state-specific factoid from CloudKit
                    self.logDebug("☁️ Successfully fetched state-specific factoid from CloudKit")
                    self.factoidOriginLog[state] = "cloudkit_state_specific"
                    completion(factoid)
                    return
                }
                
                self.logDebug("☁️ No state-specific factoid found in CloudKit, trying generic")
                
                // Try fetching a generic factoid from CloudKit
                fetchGenericFactoidFromCloudKit { [weak self] genericFactoid in
                    guard let self = self else { return completion(nil) }
                    
                    if let factoid = genericFactoid {
                        // Success with generic factoid from CloudKit
                        self.logDebug("☁️ Successfully fetched generic factoid from CloudKit")
                        self.factoidOriginLog[state] = "cloudkit_generic"
                        completion(factoid)
                        return
                    }
                    
                    self.logDebug("☁️ No generic factoid found in CloudKit, falling back to cache")
                    
                    // Now try cached state-specific factoid
                    if let cachedStateFactoid = self.getCachedFactoid(for: state) {
                        self.logDebug("💾 Using cached state-specific factoid as fallback")
                        self.factoidOriginLog[state] = "cache_state_specific_fallback"
                        completion(cachedStateFactoid)
                        return
                    }
                    
                    // Try cached generic factoid
                    if let cachedGenericFactoid = self.getCachedFactoid(for: "Generic") {
                        self.logDebug("💾 Using cached generic factoid as fallback")
                        self.factoidOriginLog[state] = "cache_generic_fallback"
                        completion(cachedGenericFactoid)
                        return
                    }
                    
                    // Last resort - basic message
                    self.logDebug("💬 Using basic welcome message as last resort")
                    self.factoidOriginLog[state] = "basic_message_last_resort"
                    completion("You've entered a new state!")
                }
            }
        } else {
            logDebug("📡 No internet - falling back to cached factoids")
            
            // Try cached state-specific factoid
            if let cachedStateFactoid = getCachedFactoid(for: state) {
                logDebug("💾 Using cached state-specific factoid (offline mode)")
                factoidOriginLog[state] = "cache_state_specific_offline"
                completion(cachedStateFactoid)
                return
            }
            
            // Try cached generic factoid
            if let cachedGenericFactoid = getCachedFactoid(for: "Generic") {
                logDebug("💾 Using cached generic factoid (offline mode)")
                factoidOriginLog[state] = "cache_generic_offline"
                completion(cachedGenericFactoid)
                return
            }
            
            // Last resort - basic message
            logDebug("💬 Using basic welcome message (offline mode)")
            factoidOriginLog[state] = "basic_message_offline"
            completion("You've entered a new state!")
        }
    }
    
    // IMPROVED: Helper to get a cached factoid from memory with better randomization
    private func getCachedFactoid(for state: String) -> String? {
        // Check if we have cached factoids for this state
        if let stateFactoids = cachedFactoids[state], !stateFactoids.isEmpty {
            // Skip default factoids if we know they're not from CloudKit
            if usedDefaultFactoids && (state == "New York" || state == "California" ||
                                      state == "Texas" || state == "Florida") {
                logDebug("📚 Skipping default hardcoded factoid for \(state)")
                return nil
            }
            
            // Log what we found in the cache
            logDebug("📚 Found \(stateFactoids.count) factoids in cache for \(state)")
            
            // Generate a more unique random factoid using timestamp as seed
            let timestamp = Date().timeIntervalSince1970
            let seed = Int(timestamp * 1000) % max(1, stateFactoids.count)
            let index = abs(seed % stateFactoids.count)
            
            // DEBUG: Log which factoid we're using
            logDebug("📚 Using factoid index \(index) of \(stateFactoids.count) for \(state)")
            
            return stateFactoids[index]
        }
        
        logDebug("📚 No factoids found in cache for \(state)")
        return nil
    }
    
    // IMPROVED: Fetch specifically state-related factoids from CloudKit with better debugging
    private func fetchSpecificStateFactoidFromCloudKit(for state: String, completion: @escaping (String?) -> Void) {
        // Create a background task for this fetch
        let taskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endFactoidFetchTask(for: state)
        }
        
        factoidFetchTasks[state] = taskId
        
        // Create query for state-specific factoids only
        let predicate = NSPredicate(format: "state == %@", state)
        let query = CKQuery(recordType: "StateFactoids", predicate: predicate)
        
        // DEBUG: Log the exact query details
        logDebug("☁️ CloudKit query - Type: StateFactoids, Predicate: state == \(state)")
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 10 // Limit to avoid excessive network usage
        var fetchedFactoids: [String] = []
        
        // DEBUG: Log the CloudKit query
        let queryTime = Date()
        cloudKitRequestLog[queryTime] = (query: "StateFactoids with state==\(state)", result: "pending")
        
        operation.recordMatchedBlock = { [weak self] (_, result) in
            switch result {
            case .success(let record):
                if let fact = record["fact"] as? String {
                    fetchedFactoids.append(fact)
                    self?.logDebug("📄 Received factoid record for \(state): \(fact.prefix(30))...")
                }
            case .failure(let error):
                self?.logDebug("⚠️ Record fetch failed: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { [weak self] result in
            guard let self = self else {
                completion(nil)
                return
            }
            
            switch result {
            case .success:
                // Update CloudKit request log
                self.cloudKitRequestLog[queryTime] = (
                    query: "StateFactoids with state==\(state)",
                    result: "success: \(fetchedFactoids.count) records")
                
                // Log success with detailed count
                self.logDebug("☁️ CloudKit query complete for \(state) - Found \(fetchedFactoids.count) factoids")
                
                // Update cache with any fetched factoids
                if !fetchedFactoids.isEmpty {
                    // Update the cache
                    if self.cachedFactoids[state] == nil {
                        self.cachedFactoids[state] = []
                    } else {
                        // Clear existing factoids for this state to ensure fresh data
                        self.cachedFactoids[state]?.removeAll()
                    }
                    
                    // Add fresh factoids to the cache
                    self.cachedFactoids[state] = fetchedFactoids
                    
                    // Save updated cache
                    self.saveCachedFactoids()
                    
                    // Return a random factoid from the results
                    if let selectedFactoid = fetchedFactoids.randomElement() {
                        // End the background task
                        self.endFactoidFetchTask(for: state)
                        
                        // Return the selected factoid
                        completion(selectedFactoid)
                        return
                    }
                } else {
                    self.logDebug("☁️ No factoids found for \(state) in CloudKit")
                }
                
                // If we get here, no factoids were found for this state
                self.endFactoidFetchTask(for: state)
                completion(nil)
                
            case .failure(let error):
                // Update CloudKit request log
                self.cloudKitRequestLog[queryTime] = (
                    query: "StateFactoids with state==\(state)",
                    result: "failure: \(error.localizedDescription)")
                
                self.logDebug("⚠️ Error fetching state factoids: \(error.localizedDescription)")
                
                // DEBUG: Add error details
                if let ckError = error as? CKError {
                    self.logDebug("⚠️ CloudKit error code: \(ckError.code.rawValue)")
                    if let serverRecord = ckError.serverRecord {
                        self.logDebug("⚠️ Server record returned: \(serverRecord.recordType)")
                    }
                    if let retryAfter = ckError.retryAfterSeconds {
                        self.logDebug("⚠️ Retry suggested after: \(retryAfter) seconds")
                    }
                }
                
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
        
        // DEBUG: Log the exact query details
        logDebug("☁️ CloudKit query - Type: StateFactoids, Predicate: state == Generic")
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 10 // Limit to avoid excessive network usage
        var fetchedFactoids: [String] = []
        
        // DEBUG: Log the CloudKit query
        let queryTime = Date()
        cloudKitRequestLog[queryTime] = (query: "StateFactoids with state==Generic", result: "pending")
        
        operation.recordMatchedBlock = { [weak self] (_, result) in
            switch result {
            case .success(let record):
                if let fact = record["fact"] as? String {
                    fetchedFactoids.append(fact)
                    self?.logDebug("📄 Received generic factoid record: \(fact.prefix(30))...")
                }
            case .failure(let error):
                self?.logDebug("⚠️ Generic record fetch failed: \(error.localizedDescription)")
            }
        }
        
        operation.queryResultBlock = { [weak self] result in
            guard let self = self else {
                completion(nil)
                return
            }
            
            switch result {
            case .success:
                // Update CloudKit request log
                self.cloudKitRequestLog[queryTime] = (
                    query: "StateFactoids with state==Generic",
                    result: "success: \(fetchedFactoids.count) records")
                
                // Log success with detailed count
                self.logDebug("☁️ CloudKit query complete for Generic - Found \(fetchedFactoids.count) factoids")
                
                // Update cache with any fetched factoids
                if !fetchedFactoids.isEmpty {
                    // Update the cache
                    if self.cachedFactoids["Generic"] == nil {
                        self.cachedFactoids["Generic"] = []
                    } else {
                        // Clear existing generic factoids to ensure fresh data
                        self.cachedFactoids["Generic"]?.removeAll()
                    }
                    
                    // Add fresh factoids to the cache
                    self.cachedFactoids["Generic"] = fetchedFactoids
                    
                    // Save updated cache
                    self.saveCachedFactoids()
                    
                    // Return a random factoid from the results
                    let selectedFactoid = fetchedFactoids.randomElement()
                    completion(selectedFactoid)
                } else {
                    // No generic factoids found
                    self.logDebug("☁️ No generic factoids found in CloudKit")
                    completion(nil)
                }
                
            case .failure(let error):
                // Update CloudKit request log
                self.cloudKitRequestLog[queryTime] = (
                    query: "StateFactoids with state==Generic",
                    result: "failure: \(error.localizedDescription)")
                
                self.logDebug("⚠️ Error fetching generic factoids: \(error.localizedDescription)")
                
                // DEBUG: Add error details
                if let ckError = error as? CKError {
                    self.logDebug("⚠️ CloudKit error code: \(ckError.code.rawValue)")
                    if let serverRecord = ckError.serverRecord {
                        self.logDebug("⚠️ Server record returned: \(serverRecord.recordType)")
                    }
                    if let retryAfter = ckError.retryAfterSeconds {
                        self.logDebug("⚠️ Retry suggested after: \(retryAfter) seconds")
                    }
                }
                
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
    
    // Helper to check internet connection with more detailed status
    private func checkInternetConnection() -> Bool {
        // First try network path monitor
        if isNetworkAvailable {
            logDebug("🌐 Network is available according to path monitor")
            return true
        }
        
        // Secondary method - check reachability to CloudKit
        logDebug("🌐 Checking CloudKit reachability as secondary network check")
        let semaphore = DispatchSemaphore(value: 0)
        var isOnline = false
        
        cloudContainer.accountStatus { [weak self] (accountStatus, error) in
            // If we can get the account status, we're likely online
            if error == nil {
                isOnline = true
                self?.logDebug("🌐 CloudKit container is reachable, network is available")
            } else if let error = error {
                self?.logDebug("🌐 CloudKit container error during network check: \(error.localizedDescription)")
            }
            semaphore.signal()
        }
        
        // Wait up to 1 second for the check
        _ = semaphore.wait(timeout: .now() + 1.0)
        
        return isOnline
    }
    
    // Setup network monitoring with more details
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                // Get current status
                let oldStatus = self?.isNetworkAvailable ?? false
                
                // Update status
                self?.isNetworkAvailable = path.status == .satisfied
                
                // Log status change
                if oldStatus != (self?.isNetworkAvailable ?? false) {
                    if let isAvailable = self?.isNetworkAvailable {
                        self?.logDebug("🌐 Network availability changed: \(isAvailable ? "ONLINE" : "OFFLINE")")
                        
                        // Log interface types
                        if isAvailable {
                            var interfaces = ""
                            if path.usesInterfaceType(.wifi) {
                                interfaces += "WiFi "
                            }
                            if path.usesInterfaceType(.cellular) {
                                interfaces += "Cellular "
                            }
                            if path.usesInterfaceType(.wiredEthernet) {
                                interfaces += "Ethernet "
                            }
                            self?.logDebug("🌐 Network interfaces: \(interfaces)")
                        }
                    }
                }
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
    }
    
    // MARK: - Cloud Sync Integration

    /// Call this when cloud sync completes to process pending notifications
    func cloudSyncDidComplete() {
        cloudSyncComplete = true
        logDebug("☁️ Cloud sync completed - processing \(pendingStateDetections.count) pending state detections")
        
        // Process any pending state detections
        for state in pendingStateDetections {
            handleDetectedState(state)
        }
        pendingStateDetections.removeAll()
        
        // Preload factoids after cloud sync completes
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.preloadFactoids(forceRefresh: true)
        }
    }
    
    // MARK: - Debug Information
    
    // Get diagnostic information for debugging
    func getDiagnosticInfo() -> String {
        var info = "==== Factoid System Diagnostic Info ====\n"
        
        // Network status
        info += "Network Status: \(isNetworkAvailable ? "ONLINE" : "OFFLINE")\n"
        
        // CloudKit status
        info += "CloudKit Container: \(String(describing: cloudContainer.containerIdentifier))\n"
        
        // Cache info
        info += "Cache Age: \(lastFactoidFetchTime != nil ? "\(Int(Date().timeIntervalSince(lastFactoidFetchTime!)/3600))h" : "never fetched")\n"
        info += "Cached States: \(cachedFactoids.keys.joined(separator: ", "))\n"
        info += "Factoid Stats - Fetch Attempts: \(factoidFetchAttempts), Successes: \(factoidFetchSuccesses)\n"
        
        // Recent factoid origins
        info += "Recent Factoid Origins:\n"
        for (state, origin) in factoidOriginLog {
            info += "  \(state): \(origin)\n"
        }
        
        // Recent CloudKit requests
        info += "Recent CloudKit Requests:\n"
        let sortedRequests = cloudKitRequestLog.sorted(by: { $0.key > $1.key })
        for (date, request) in sortedRequests.prefix(5) {
            let timeAgo = Int(Date().timeIntervalSince(date))
            info += "  \(timeAgo)s ago: \(request.query) - \(request.result)\n"
        }
        
        return info
    }
}
