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
        
        // IMPROVED: Only clear factoid cache if it's older than a week
        if let lastFetch = UserDefaults.standard.object(forKey: "lastFactoidFetchTime") as? Date,
           Date().timeIntervalSince(lastFetch) > 7 * 24 * 3600 {
            logDebug("📚 Factoid cache is older than a week - clearing to get fresh factoids")
            clearFactoidCache()
        } else {
            logDebug("📚 Keeping existing factoid cache on startup for reliability")
        }
        
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
        // Log the last notified state for debugging
        let lastNotifiedState = UserDefaults.standard.string(forKey: "lastNotifiedState")
        logDebug("🔔 App became active - last notified state: \(lastNotifiedState ?? "none")")
        
        // We rely on the StateDetectionService's didJustEnterForeground flag
        // The notification logic is now handled directly in that service
        // We only need to ensure the last notified state is in sync
        UserDefaults.standard.synchronize()
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
        operation.resultsLimit = 500 // Increased to fetch ALL possible factoids for all states
        
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
                
                // IMPROVED: Only clear cache for states that were successfully fetched
                // First make a copy of the current cache
                let previousCache = self.cachedFactoids
                
                // Store info on what we're updating for logging
                var updatedStates: Set<String> = []
                var preservedStates: Set<String> = []
                var totalFactoids = 0
                
                // Now add the fresh factoids to the cache, replacing only those states we got new data for
                for (state, facts) in newFactoids {
                    if !facts.isEmpty {
                        self.cachedFactoids[state] = facts
                        updatedStates.insert(state)
                        totalFactoids += facts.count
                    }
                }
                
                // Preserve any states in the previous cache that weren't updated
                for (state, facts) in previousCache {
                    if (self.cachedFactoids[state] == nil || self.cachedFactoids[state]?.isEmpty == true) && !facts.isEmpty {
                        self.cachedFactoids[state] = facts
                        preservedStates.insert(state)
                        totalFactoids += facts.count
                    }
                }
                
                // Log what happened for debugging
                self.logDebug("📚 Updated factoids for \(updatedStates.count) states: \(updatedStates.sorted().joined(separator: ", "))")
                if !preservedStates.isEmpty {
                    self.logDebug("📚 Preserved factoids for \(preservedStates.count) states: \(preservedStates.sorted().joined(separator: ", "))")
                }
                self.logDebug("📚 Total factoids in cache: \(totalFactoids) for \(self.cachedFactoids.count) states")
                
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
    
    // Generate a reasonable default factoid for any US state
    private func getDefaultFactoidForState(_ state: String) -> String {
        // Dictionary of basic but informative state factoids
        let stateFactoids: [String: String] = [
            "Alabama": "Welcome to Alabama, known as the Heart of Dixie and home to significant civil rights history.",
            "Alaska": "Welcome to Alaska, the largest U.S. state with more coastline than all other states combined!",
            "Arizona": "Welcome to Arizona, home of the Grand Canyon and stunning desert landscapes.",
            "Arkansas": "Welcome to Arkansas, known as The Natural State for its beautiful mountains, rivers, and hot springs.",
            "California": "Welcome to California, the most populous US state and home to Hollywood, Silicon Valley, and stunning coastlines.",
            "Colorado": "Welcome to Colorado, known for the Rocky Mountains and having the highest average elevation of any state.",
            "Connecticut": "Welcome to Connecticut, one of the original 13 colonies and known as the Constitution State.",
            "Delaware": "Welcome to Delaware, the First State to ratify the U.S. Constitution in 1787.",
            "Florida": "Welcome to Florida, known for its beaches, theme parks, and being home to the Kennedy Space Center.",
            "Georgia": "Welcome to Georgia, the Peach State, founded in 1732 as the last of the original 13 colonies.",
            "Hawaii": "Welcome to Hawaii, the only U.S. state made up entirely of islands and home to active volcanoes.",
            "Idaho": "Welcome to Idaho, famous for its potatoes and home to part of Yellowstone National Park.",
            "Illinois": "Welcome to Illinois, home to Chicago, one of America's largest cities, and Abraham Lincoln's home state.",
            "Indiana": "Welcome to Indiana, the Hoosier State and home to the famous Indianapolis 500 race.",
            "Iowa": "Welcome to Iowa, a leading agricultural producer known for its rolling plains and farmland.",
            "Kansas": "Welcome to Kansas, the Sunflower State located in the heart of America's breadbasket.",
            "Kentucky": "Welcome to Kentucky, famous for bourbon, horse racing, and the Kentucky Derby.",
            "Louisiana": "Welcome to Louisiana, known for its unique Creole and Cajun culture, cuisine, and Mardi Gras celebrations.",
            "Maine": "Welcome to Maine, known for its rocky coastline, maritime history, and delicious lobster.",
            "Maryland": "Welcome to Maryland, home to the Chesapeake Bay and the city of Baltimore.",
            "Massachusetts": "Welcome to Massachusetts, a state rich in American history and home to Harvard University.",
            "Michigan": "Welcome to Michigan, surrounded by four of the five Great Lakes and divided into two peninsulas.",
            "Minnesota": "Welcome to Minnesota, Land of 10,000 Lakes and home to the headwaters of the Mississippi River.",
            "Mississippi": "Welcome to Mississippi, named after the Mississippi River forming its western boundary.",
            "Missouri": "Welcome to Missouri, known as the Gateway to the West and home to the iconic St. Louis Arch.",
            "Montana": "Welcome to Montana, Big Sky Country with more species of mammals than any other state.",
            "Nebraska": "Welcome to Nebraska, where the tree-planting holiday of Arbor Day originated in 1872.",
            "Nevada": "Welcome to Nevada, home to Las Vegas and more mountain ranges than any other lower 48 state.",
            "New Hampshire": "Welcome to New Hampshire, whose motto 'Live Free or Die' reflects its independent spirit.",
            "New Jersey": "Welcome to New Jersey, one of the original 13 colonies with more than 130 miles of Atlantic coastline.",
            "New Mexico": "Welcome to New Mexico, Land of Enchantment with unique adobe architecture and rich Native American heritage.",
            "New York": "Welcome to New York, home to New York City, the most populous city in the United States.",
            "North Carolina": "Welcome to North Carolina, home to the Wright Brothers' first flight and the Great Smoky Mountains.",
            "North Dakota": "Welcome to North Dakota, known for its badlands, agriculture, and the geographic center of North America.",
            "Ohio": "Welcome to Ohio, the Buckeye State and birthplace of seven U.S. presidents.",
            "Oklahoma": "Welcome to Oklahoma, where the wind comes sweepin' down the plain and Native American culture thrives.",
            "Oregon": "Welcome to Oregon, known for diverse landscapes from Pacific coastline to mountains and high desert.",
            "Pennsylvania": "Welcome to Pennsylvania, where the Declaration of Independence and Constitution were signed.",
            "Rhode Island": "Welcome to Rhode Island, the smallest U.S. state with a big maritime heritage.",
            "South Carolina": "Welcome to South Carolina, known for its palmetto trees, historic Charleston, and beautiful beaches.",
            "South Dakota": "Welcome to South Dakota, home to Mount Rushmore and Badlands National Park.",
            "Tennessee": "Welcome to Tennessee, birthplace of country music and home to the Great Smoky Mountains.",
            "Texas": "Welcome to Texas, the Lone Star State and the second largest state in both area and population.",
            "Utah": "Welcome to Utah, home to stunning national parks including Zion, Bryce Canyon, and Arches.",
            "Vermont": "Welcome to Vermont, known for its maple syrup, beautiful fall foliage, and Green Mountains.",
            "Virginia": "Welcome to Virginia, birthplace of eight U.S. Presidents and home to historic Jamestown.",
            "Washington": "Welcome to Washington, known for its evergreen forests, Mount Rainier, and tech industry.",
            "West Virginia": "Welcome to West Virginia, the Mountain State completely within the Appalachian Mountains.",
            "Wisconsin": "Welcome to Wisconsin, America's Dairyland and home to over 15,000 lakes.",
            "Wyoming": "Welcome to Wyoming, home to Yellowstone, the first national park in the United States."
        ]
        
        // If we have a factoid for this state, use it
        if let factoid = stateFactoids[state] {
            return factoid
        }
        
        // If we don't have a specific factoid, create a generic one for the state
        return "Welcome to \(state)! You've added another state to your collection."
    }
    
    // Create minimal fallback factoids for offline use
    private func createFallbackFactoids() {
        logDebug("📚 Creating basic factoids cache for offline use")
        
        // Flag that we're using default factoids
        usedDefaultFactoids = true
        
        // Create generic factoid
        cachedFactoids["Generic"] = [
            "You've entered a new state!",
            "Welcome to a new state on your journey!",
            "Another state to add to your collection!"
        ]
        
        // Add default factoids for all 50 states to ensure we always have content
        let allStates = [
            "Alabama", "Alaska", "Arizona", "Arkansas", "California", 
            "Colorado", "Connecticut", "Delaware", "Florida", "Georgia", 
            "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", 
            "Kansas", "Kentucky", "Louisiana", "Maine", "Maryland", 
            "Massachusetts", "Michigan", "Minnesota", "Mississippi", "Missouri", 
            "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey", 
            "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio", 
            "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island", "South Carolina", 
            "South Dakota", "Tennessee", "Texas", "Utah", "Vermont", 
            "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"
        ]
        
        for state in allStates {
            if cachedFactoids[state] == nil {
                cachedFactoids[state] = [getDefaultFactoidForState(state)]
            }
        }
        
        logDebug("📚 Created default factoids for \(cachedFactoids.count) states")
        
        // Save the fallback factoids
        saveCachedFactoids()
    }
    
    private func saveSpecificStateFactoid(state: String, factoids: [String]) {
        // This method updates a single state's factoids in UserDefaults without saving the entire cache
        // Much more efficient for background operation
        
        // First retrieve existing cache from UserDefaults
        if let savedData = UserDefaults.standard.data(forKey: "CachedFactoids"),
           var existingCache = try? JSONDecoder().decode([String: [String]].self, from: savedData) {
            
            // Update just this state
            existingCache[state] = factoids
            
            // Save back the updated cache
            if let encodedData = try? JSONEncoder().encode(existingCache) {
                UserDefaults.standard.set(encodedData, forKey: "CachedFactoids")
                logDebug("💾 Updated factoids for \(state) in UserDefaults (\(factoids.count) factoids)")
                return
            }
        }
        
        // If we can't update existing, fall back to full save
        saveCachedFactoids()
    }
    
    private func saveCachedFactoids() {
        guard !cachedFactoids.isEmpty else { return }
        
        // Thread-safe way to check if we're in background mode
        // Never access UIApplication from background threads
        var isInBackground = false
        if Thread.isMainThread {
            isInBackground = UIApplication.shared.applicationState == .background
        } else {
            // When on background thread, just be conservative with logging
            isInBackground = true
        }
        
        // Save to UserDefaults for offline access
        if let encodedData = try? JSONEncoder().encode(cachedFactoids) {
            UserDefaults.standard.set(encodedData, forKey: "CachedFactoids")
            
            // Simplified logging for background mode
            if isInBackground {
                logDebug("💾 Saved factoid cache to UserDefaults (background mode)")
            } else {
                // Full logging in foreground
                logDebug("💾 Saved \(cachedFactoids.count) state factoid categories to UserDefaults")
                
                // DEBUG: Log summary of what's in the cache
                var cacheSummary = ""
                for (state, facts) in cachedFactoids {
                    cacheSummary += "\(state): \(facts.count) factoids, "
                }
                logDebug("💾 Cache contents: \(cacheSummary)")
            }
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
            // IMPROVED: Increased timeout for better chances of getting specific factoids for all states
            let timeoutDuration: TimeInterval = 12.0 // 12 seconds gives more time for slow connections
            
            // Log factoid fetch attempt details
            let hasCachedFactoids = cachedFactoids[state] != nil && !(cachedFactoids[state]?.isEmpty ?? true)
            logDebug("☁️ Attempting CloudKit fetch for state: \(state) with \(timeoutDuration)s timeout")
            logDebug("📡 Network info: Available=\(isNetworkAvailable), Interfaces=\(getNetworkInterfaces())")
            logDebug("📚 Cache status: Has \(state) factoids=\(hasCachedFactoids ? "YES" : "NO"), Count=\(cachedFactoids[state]?.count ?? 0)")
            
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.logDebug("⏰ CloudKit fetch for \(state) timed out after \(timeoutDuration)s, falling back to cache")
                
                // Try cached state-specific factoid first
                if let cachedStateFactoid = self?.getCachedFactoid(for: state) {
                    self?.logDebug("💾 Using cached state-specific factoid for \(state) after CloudKit timeout")
                    self?.factoidOriginLog[state] = "cache_state_specific_after_timeout"
                    completion(cachedStateFactoid)
                    return
                }
                
                // Create a default state factoid if needed
                if let self = self {
                    // Make sure we have at least one factoid for this state
                    let defaultFactoid = self.getDefaultFactoidForState(state)
                    self.logDebug("📝 No cached factoid found for \(state), using generated default factoid")
                    self.factoidOriginLog[state] = "generated_default_factoid"
                    
                    // Save this factoid to the cache for future use
                    if self.cachedFactoids[state] == nil {
                        self.cachedFactoids[state] = [defaultFactoid]
                        self.saveCachedFactoids()
                    }
                    
                    completion(defaultFactoid)
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
                self?.factoidOriginLog[state] = "basic_message_last_resort"
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
            // Always use any available factoids, regardless of source
            // We've improved our default factoids to be state-specific
            
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
        
        // Ensure we have a fallback factoid for this state
        if cachedFactoids[state] == nil || cachedFactoids[state]?.isEmpty == true {
            // Create a default factoid for this state
            let defaultFactoid = getDefaultFactoidForState(state)
            cachedFactoids[state] = [defaultFactoid]
            saveCachedFactoids()
            logDebug("📚 Created fallback factoid for \(state) before CloudKit query")
        }
        
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
                
                // Log detailed factoid info if we have any
                if !fetchedFactoids.isEmpty && fetchedFactoids.count <= 3 {
                    // Only log full details for small numbers of factoids
                    for (index, fact) in fetchedFactoids.enumerated() {
                        self.logDebug("📄 State factoid[\(index)]: \(fact.prefix(50))...")
                    }
                }
                
                // Update cache with any fetched factoids
                if !fetchedFactoids.isEmpty {
                    // Add fresh factoids to the cache in memory
                    self.cachedFactoids[state] = fetchedFactoids
                    
                    // Thread-safe handling of UI state
                    if Thread.isMainThread && UIApplication.shared.applicationState == .background {
                        // If we're on main thread and can safely check, use the efficient method
                        self.saveSpecificStateFactoid(state: state, factoids: fetchedFactoids)
                    } else {
                        // Otherwise, use the safe method that handles thread context internally
                        self.saveCachedFactoids()
                    }
                    
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
                    // Add fresh factoids to the cache in memory
                    self.cachedFactoids["Generic"] = fetchedFactoids
                    
                    // Thread-safe handling of UI state
                    if Thread.isMainThread && UIApplication.shared.applicationState == .background {
                        // If we're on main thread and can safely check, use the efficient method
                        self.saveSpecificStateFactoid(state: "Generic", factoids: fetchedFactoids)
                    } else {
                        // Otherwise, use the safe method that handles thread context internally
                        self.saveCachedFactoids()
                    }
                    
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
        
        // Only preload all factoids when app is in foreground to save background processing time
        // Use thread-safe approach to check app state
        var skipPreload = true
        
        if Thread.isMainThread {
            skipPreload = UIApplication.shared.applicationState == .background
        }
        
        if !skipPreload {
            logDebug("📚 App in foreground - preloading all factoids")
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.preloadFactoids(forceRefresh: true)
            }
        } else {
            logDebug("📚 App in background - skipping full factoid preload to conserve resources")
        }
    }
    
    // MARK: - Debug Information
    
    // Helper method to get current network interfaces
    private func getNetworkInterfaces() -> String {
        guard let networkMonitor = networkMonitor else { return "No monitor" }
        
        var interfaces = ""
        if networkMonitor.currentPath.usesInterfaceType(.wifi) {
            interfaces += "WiFi "
        }
        if networkMonitor.currentPath.usesInterfaceType(.cellular) {
            interfaces += "Cellular "
        }
        if networkMonitor.currentPath.usesInterfaceType(.wiredEthernet) {
            interfaces += "Ethernet "
        }
        if interfaces.isEmpty {
            interfaces = "None"
        }
        return interfaces
    }
    
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
