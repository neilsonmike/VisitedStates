import Foundation
import UserNotifications
import CloudKit
import SwiftUI

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    /// This property should be set by the UI (e.g., in ContentView) so that
    /// NotificationManager uses the same settings as the app.
    var appSettings: AppSettings?
    
    private let cooldownKeyPrefix = "lastNotified_"
    private let cooldownInterval: TimeInterval = 300 // 5 minutes
    private let defaultNotificationDelay: TimeInterval = 0.1 // nearly immediate
    private var lastNotifiedState: String? = nil
    private var lastNotificationTime: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 300  // 5 minutes cooldown
    
    // Local fallback factoids (used when useFallback is true)
    let fallbackFactoids: [String] = [
        "Did you know? This state is powered by giggles!",
        "Fun fact: Local squirrels throw secret acorn parties!",
        "Breaking news: This state is certified 100% fun!",
        "Alert: Even the lampposts here dance at midnight!",
        "Trivia: This state is home to the world's happiest potholes!"
    ]
    
    override private init() {
        super.init() // Ensure superclass is initialized first

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else {
                print("Notification permission denied: \(error?.localizedDescription ?? "unknown error")")
            }
        }
        
        UNUserNotificationCenter.current().delegate = self // Now it's safe to use 'self'
    }
    
    /// Schedules a notification for the given state if notifications are enabled and the cooldown period has passed.
    func scheduleNotification(for state: String) {
        // Check if notifications are enabled from the shared settings.
        if let settings = appSettings, !settings.notificationsEnabled {
            print("Notifications are disabled. Skipping scheduling for \(state).")
            return
        }
        
        let key = cooldownKeyPrefix + state
        
        // Check if we already notified for this exact state
        if state == lastNotifiedState {
            print("\(state) was the last notified state, skipping notification.")
            return
        }
        
        if let lastNotified = UserDefaults.standard.object(forKey: key) as? Date {
            let timeSince = Date().timeIntervalSince(lastNotified)
            print("Time since last notification for \(state): \(timeSince) seconds")
            if timeSince < cooldownInterval {
                print("Notification for \(state) is still in cooldown.")
                return
            }
        }
        
        print("Scheduling notification for state: \(state)")
        fetchFactoid(for: state, useFallback: true) { factoid in
            let factText = factoid ?? "Welcome!"
            print("Fetched factoid: \(factText)")
            self.sendNotification(for: state, fact: factText)
            UserDefaults.standard.set(Date(), forKey: key)
            
            // Also record the last notified state
            UserDefaults.standard.set(state, forKey: "lastNotifiedState")
        }
    }
    
    /// Fetches a factoid for the given state from CloudKit.
    /// If useFallback is true and no fact is found, returns a random local fallback.
    /// If useFallback is false, returns nil if no CloudKit factoid is found.
    ///
    /// Note: Generic factoids should have their "state" field set to an empty string ("") in CloudKit.
    func fetchFactoid(for state: String, useFallback: Bool = true, completion: @escaping (String?) -> Void) {
        print("Fetching factoid for state: \(state)")
        // Using an IN predicate with an array containing the provided state and an empty string.
        let predicate = NSPredicate(format: "state IN %@", [state, "Generic"])
        print("Predicate used: \(predicate)")
        let query = CKQuery(recordType: "StateFactoids", predicate: predicate)
        
        // Accessing CloudKit container using defined constant
        let container = CKContainer(identifier: Constants.cloudContainerID)
        let database = container.publicCloudDatabase
        
        print("Performing query on container: \(container)")
        database.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error fetching factoids: \(error)")
                completion(nil)
                return
            }
            if let records = records {
                print("Fetched \(records.count) record(s) from CloudKit.")
            } else {
                print("No records fetched from CloudKit.")
            }
            
            guard let records = records, !records.isEmpty else {
                print("No factoid records found.")
                completion(nil)
                return
            }
            let factoids = records.compactMap { $0["fact"] as? String }
            if let chosen = factoids.randomElement() {
                print("Randomly selected factoid: \(chosen)")
                completion(chosen)
            } else {
                print("No fact string found in the records.")
                completion(useFallback ? self.fallbackFactoids.randomElement() : nil)
            }
        }
    }
    
    private func sendNotification(for state: String, fact: String) {
        let content = UNMutableNotificationContent()
        content.title = "Welcome to \(state)!"
        content.body = fact
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: defaultNotificationDelay, repeats: false)
        let requestID = "stateNotification_\(state)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification for \(state): \(error)")
            } else {
                print("Notification scheduled for \(state).")
            }
        }
    }
    
    func handleDetectedState(_ state: String) {
        guard state != lastNotifiedState else {
            print("Already notified for state \(state). Skipping notification.")
            return
        }

        lastNotifiedState = state

        fetchFactoid(for: state) { factoid in
            let factText = factoid ?? "Welcome!"
            self.sendNotification(for: state, fact: factText)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Present notifications even when the app is in the foreground
        completionHandler([.banner, .sound])
    }
}
