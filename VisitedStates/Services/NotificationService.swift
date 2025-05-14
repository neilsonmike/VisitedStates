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
    
    // Monitoring and diagnostic settings
    private let enableDebugLogging = false  // Keep this set to false for production

    // Network monitor
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
    // Changed to internal for extension use
    var factoidOriginLog: [String: String] = [:]  // Tracks where each factoid came from
    private var cloudKitRequestLog: [Date: (query: String, result: String)] = [:]  // Logs CloudKit requests
    private var factoidFetchAttempts = 0
    private var factoidFetchSuccesses = 0
    
    // Cache tracking for factoid system
    private var factoidCacheInitialized = false
    
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

        // IMPORTANT: Always purge any potential default factoids from previous versions
        // to ensure only Google Sheets factoids are ever used
        purgeNonGoogleSheetsFactoids()

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

        // Pre-fetch the factoid right away to ensure it's ready when needed
        // Store a one-time flag to track if we already fetched during this notification cycle
        let prefetchKey = "PREFETCH_IN_PROGRESS_\(state)"
        UserDefaults.standard.set(true, forKey: prefetchKey)
        
        fetchFactoidWithNetworkPriority(for: state) { factoid in
            // Store the factoid directly in UserDefaults with a timestamp
            if let factoid = factoid {
                UserDefaults.standard.set(factoid, forKey: "DIRECT_FACTOID_\(state)")
                UserDefaults.standard.set(Date(), forKey: "FACTOID_TIMESTAMP_\(state)")
                UserDefaults.standard.synchronize()
            }
            
            // Indicate pre-fetch is complete
            UserDefaults.standard.removeObject(forKey: prefetchKey)
            UserDefaults.standard.synchronize()
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
                // We no longer schedule the notification here - delay is handled by StateDetectionService
                // Just update tracking
                statesVisitedBeforeCurrentSession.insert(state)
            } else {
                logDebug("🔔 Skipping notification for already visited state: \(state) (notify only new states is enabled)")
                statesVisitedBeforeCurrentSession.insert(state)
            }
        } else {
            // Notify for all state changes - but actual scheduling is handled by StateDetectionService with delay
            logDebug("🔔 Will notify for state: \(state)")
            statesVisitedBeforeCurrentSession.insert(state)
        }
    }
    
    func scheduleStateEntryNotification(for state: String) {
        // Create a background task for notification process - critical for background operation
        let bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask(for: state)
        }

        // Store the task ID for later cleanup
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
        
        // Skip if "notify only new states" setting is enabled and this is not a new state
        if settings.notifyOnlyNewStates.value && settings.hasVisitedState(state) {
            logDebug("🔔 Skipping notification for already visited state \(state) (notify only new states is enabled)")
            endBackgroundTask(for: state)
            return
        }

        // Track when this state was last notified for duplicate prevention
        let key = cooldownKeyPrefix + state
        UserDefaults.standard.set(Date(), forKey: key)

        // Check if app is in foreground or background
        var appState = "unknown"
        var isInBackground = false
        if Thread.isMainThread {
            isInBackground = UIApplication.shared.applicationState != .active
            appState = isInBackground ? "background" : "foreground"
        } else {
            DispatchQueue.main.sync {
                isInBackground = UIApplication.shared.applicationState != .active
                appState = isInBackground ? "background" : "foreground"
            }
        }

        print("🔔 Scheduling notification for \(state) while app is in \(appState)")

        // Reset tracking for this factoid fetch
        factoidOriginLog[state] = "unknown"
        factoidFetchAttempts += 1
        
        // First check if pre-fetch is already complete
        if let directFactoid = UserDefaults.standard.string(forKey: "DIRECT_FACTOID_\(state)") {
            // Use the pre-fetched factoid directly
            factoidOriginLog[state] = "pre-fetched from UserDefaults"
            
            // Send notification with pre-fetched factoid
            sendEnhancedNotification(for: state, fact: directFactoid)
            
            // Update tracking
            UserDefaults.standard.set(Date(), forKey: key)
            self.lastNotifiedState = state
            
            // End background task after notification is scheduled
            self.endBackgroundTask(for: state)
            return
        }
        
        // Check if pre-fetch is in progress
        let prefetchKey = "PREFETCH_IN_PROGRESS_\(state)"
        if UserDefaults.standard.bool(forKey: prefetchKey) {
            // Pre-fetch is in progress, wait for a short time to see if it completes
            
            // Wait up to 1 second for pre-fetch to complete (suitable for foreground operation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    return
                }
                
                // Check again if factoid is now available
                if let directFactoid = UserDefaults.standard.string(forKey: "DIRECT_FACTOID_\(state)") {
                    // Use the newly pre-fetched factoid
                    self.factoidOriginLog[state] = "pre-fetched (with wait)"
                    
                    // Send notification with pre-fetched factoid
                    self.sendEnhancedNotification(for: state, fact: directFactoid)
                    
                    // Update tracking
                    UserDefaults.standard.set(Date(), forKey: key)
                    self.lastNotifiedState = state
                    
                    // End background task after notification is scheduled
                    self.endBackgroundTask(for: state)
                    return
                }
                
                // If still not available, continue with normal flow
                self.continueFactoidFetchForNotification(state: state, bgTask: bgTask, key: key, isInBackground: isInBackground)
            }
            return
        }

        // If no pre-fetch in progress, continue with normal flow
        continueFactoidFetchForNotification(state: state, bgTask: bgTask, key: key, isInBackground: isInBackground)
    }
    
    // Helper method to continue factoid fetch for notification after checking pre-fetch status
    private func continueFactoidFetchForNotification(state: String, bgTask: UIBackgroundTaskIdentifier, key: String, isInBackground: Bool) {
        // In background mode, prioritize showing notification over fetching fresh factoids
        if isInBackground && cachedFactoids[state] != nil && !cachedFactoids[state]!.isEmpty {
            // Use cached factoid immediately for background notifications
            let cachedFactoid = cachedFactoids[state]!.first!
            factoidOriginLog[state] = "cache (background mode)"

            // Send notification immediately in background mode
            sendEnhancedNotification(for: state, fact: cachedFactoid)

            // Update tracking
            UserDefaults.standard.set(Date(), forKey: key)
            self.lastNotifiedState = state

            // End background task after notification is scheduled
            self.endBackgroundTask(for: state)
            return
        }

        // For foreground or when no cache is available, fetch factoid with network priority
        fetchFactoidWithNetworkPriority(for: state) { [weak self] factoid in
            guard let self = self else {
                UIApplication.shared.endBackgroundTask(bgTask)
                return
            }
            
            // Schedule notification with time delay for better background delivery
            // In foreground, this will still be scheduled but will be suppressed by the delegate
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
        // Check if this is a state entry notification
        let categoryIdentifier = notification.request.content.categoryIdentifier
        if categoryIdentifier == "STATE_ENTRY" {
            // When app is in foreground, suppress system notifications for state entry
            // because we'll show our custom in-app notification instead
            logDebug("🔕 Suppressing system state notification in foreground")
            completionHandler([])
            return
        }

        // For other notifications, present them even when app is in foreground (but NO badge)
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
    
    // Controlled logging method
    private func logDebug(_ message: String) {
        // Only print logs when debug logging is enabled
        if enableDebugLogging {
            print("NotificationService: \(message)")
        }
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
        // Check if app is in foreground or background
        var isInForeground = false
        if Thread.isMainThread {
            isInForeground = UIApplication.shared.applicationState == .active
        } else {
            DispatchQueue.main.sync {
                isInForeground = UIApplication.shared.applicationState == .active
            }
        }

        // Note that we still schedule the notification even if app is in foreground,
        // but it will be suppressed by our UNUserNotificationCenterDelegate implementation
        let appState = isInForeground ? "foreground" : "background"
        print("🔔 Sending system notification for \(state) in \(appState) mode")

        let content = UNMutableNotificationContent()
        content.title = "Welcome to \(state)!"

        // Always set some content in the body for both foreground and background notifications
        if let factText = fact, !factText.isEmpty {
            content.body = factText
        } else {
            // Use our simpler alternative message that doesn't repeat the title
            content.body = "Enjoy your stay!"
        }

        // Use default sound for all notifications - critical for background visibility
        content.sound = UNNotificationSound.default

        // Set badge to 0 in notification content
        content.badge = 0

        // Background notifications need to be high priority for delivery
        if #available(iOS 15.0, *) {
            // Make background notifications time-sensitive to improve delivery chances
            if !isInForeground {
                content.interruptionLevel = .timeSensitive
                content.relevanceScore = 1.0
            } else {
                // Regular priority for foreground
                content.interruptionLevel = .active
                content.relevanceScore = 0.7
            }
        }

        // Add the state as a category identifier for potential actions
        content.categoryIdentifier = "STATE_ENTRY"

        // Add custom data for handling
        content.userInfo = ["state": state]

        // CRITICAL FIX: In background mode, use immediate delivery for reliability
        let trigger: UNNotificationTrigger
        if isInForeground {
            // In foreground, use a short delay so our in-app UI has time to appear first
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: notificationDelay,
                repeats: false
            )
        } else {
            // In background, must be immediate for reliable delivery
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 0.1, // Almost immediate for background
                repeats: false
            )
        }

        // Create unique ID for this notification
        let requestID = "stateNotification_\(state)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: trigger
        )

        // Schedule the notification
        userNotificationCenter.add(request) { [weak self] error in
            if let error = error {
                print("⚠️ Error scheduling notification for \(state): \(error.localizedDescription)")
            } else {
                print("✅ System notification scheduled for \(state) in \(appState) mode")
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
    
    // Purge all potentially default factoids from the cache to ensure only Google Sheets factoids are used
    private func purgeNonGoogleSheetsFactoids() {
        print("🧹 Purging all non-Google Sheets factoids from the cache")

        // Attempt to fetch and decode the current cache
        if let savedData = UserDefaults.standard.data(forKey: "CachedFactoids") {
            // We'll log what we find but not modify it yet - we'll do a full clear instead
            if let existingCache = try? JSONDecoder().decode([String: [String]].self, from: savedData) {
                // Log what we're purging
                print("📚 Found factoid cache with \(existingCache.count) states and \(existingCache.values.flatMap { $0 }.count) total factoids")
                print("📚 Clearing all cached factoids to ensure only Google Sheets data is used")
            }
        }

        // Simple and safe approach: completely remove all cached factoids
        UserDefaults.standard.removeObject(forKey: "CachedFactoids")

        // Also remove any individual factoids that might have been separately cached
        for state in USStates.all {
            UserDefaults.standard.removeObject(forKey: "DIRECT_FACTOID_\(state)")
        }

        // Reset in-memory cache as well
        cachedFactoids.removeAll()

        // Force a reload from Google Sheets on next use
        UserDefaults.standard.removeObject(forKey: "lastFactoidFetchTime")

        // Synchronize to make sure changes are saved
        UserDefaults.standard.synchronize()

        print("✅ Factoid cache has been completely purged - only Google Sheets factoids will be used going forward")
    }

    // Modified preload method that only loads cached factoids, never creates fallbacks
    private func preloadFactoids(forceRefresh: Bool = false, completion: (() -> Void)? = nil) {
        // Avoid multiple concurrent preloads
        guard !isPreloadingFactoids else {
            logDebug("📚 Factoid preload already in progress, skipping")
            completion?()
            return
        }

        // Simply load any cached factoids from UserDefaults - NEVER create defaults
        loadCachedFactoids()

        // Log cache state
        if !cachedFactoids.isEmpty {
            logDebug("📚 Loaded \(cachedFactoids.count) states from cache")
        } else {
            logDebug("📚 No factoids found in cache - will rely on Google Sheets API for factoids")
        }

        // Mark as complete
        isPreloadingFactoids = false
        completion?()
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
    
    // MARK: - Public methods for Google Sheets extension
    
    /// Public method to update cached factoids from Google Sheets
    /// This is used by the NotificationService+GoogleSheets extension
    func updateCachedFactoids(for state: String, with factoids: [String]) {
        logDebug("📦 Caching \(factoids.count) factoids for \(state) from Google Sheets")
        
        // Update in-memory cache
        cachedFactoids[state] = factoids
        
        // Save to UserDefaults for persistence
        saveCachedFactoids()
        
        // Update last fetch time
        lastFactoidFetchTime = Date()
    }
    
    // MARK: - New factoid selection logic
    
    // Factoid fetching strategy using Google Sheets
    private func fetchFactoidWithNetworkPriority(for state: String, completion: @escaping (String?) -> Void) {
        // Check if we already have a direct factoid available in UserDefaults
        // This would have been set by a previous successful Google Sheets fetch
        if let directFactoid = UserDefaults.standard.string(forKey: "DIRECT_FACTOID_\(state)") {
            // Use it immediately for fast response
            completion(directFactoid)
            return
        }
        
        // Try to fetch from Google Sheets first
        if checkAndUseGoogleSheets(for: state, completion: completion) {
            // Google Sheets request was made - this will handle caching successful fetches
            return
        }

        // Fallback: check cache if Google Sheets connection fails
        loadCachedFactoids()

        // Check if we have a cached factoid from previous fetches
        if let cachedFactoid = getCachedFactoid(for: state) {
            completion(cachedFactoid)
            return
        }

        // No cached factoids available - use simple welcome message
        completion("Enjoy your stay!")
    }
    
    // Helper to get a cached factoid - always returns the first one for consistency
    // Has internal access for extension use
    func getCachedFactoid(for state: String) -> String? {
        // Check if we have cached factoids for this state
        if let stateFactoids = cachedFactoids[state], !stateFactoids.isEmpty {
            // Always use the first factoid for consistency
            let factoid = stateFactoids[0]

            // In debug builds, add a [CACHED] prefix to easily identify the source
            #if DEBUG
                return "[CACHED] \(factoid)"
            #else
                return factoid
            #endif
        }

        logDebug("📚 No factoids found in cache for \(state)")
        return nil
    }
    
    // We've removed all CloudKit factoid-related methods since we now use Google Sheets exclusively
    // The caching and loading logic for factoids remains in place to support offline mode
    
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
