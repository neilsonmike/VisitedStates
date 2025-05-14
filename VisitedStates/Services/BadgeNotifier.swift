import Foundation
import UIKit
import SwiftUI

/// Service for handling badge notification logic
class BadgeNotifier {
    
    /// Trigger a state notification with earned badges
    static func handleStateWithBadges(state: String, visitedStates: [String], getFactoid: ((String) -> String?)? = nil) {
        print("🏆 Checking for badge achievements for \(state)")
        
        // Create badge service instance
        let badgeService = BadgeTrackingService()
        
        // Check for newly earned badges
        let newlyEarnedBadges = badgeService.checkForNewBadges(
            allBadges: AchievementBadgeProvider.allBadges,
            visitedStates: visitedStates
        )
        
        print("🏆 Found \(newlyEarnedBadges.count) newly earned badges")
        
        // Check if we're in a special case - app just became active and state already notified
        let didJustBecomeActive = UserDefaults.standard.bool(forKey: "didJustBecomeActive")
        let lastNotifiedState = UserDefaults.standard.string(forKey: "lastNotifiedState")
        let skipStateNotification = didJustBecomeActive && lastNotifiedState == state
        
        // If the app just became active and this state was already notified,
        // skip the notification unless badges were earned
        if skipStateNotification && newlyEarnedBadges.isEmpty {
            print("🏆 Skipping notification - app just became active and state was already notified")
            return
        }
        
        // Get factoid for the state from notification service if provided
        var factoid: String?
        if let getFactoidFunc = getFactoid {
            factoid = getFactoidFunc(state)
        }
        
        // If no factoid, create a simple welcome message
        if factoid == nil {
            factoid = "Enjoy your stay!"
        }
        
        // Prepare notification contents
        var notification: [String: Any] = [:]
        
        if !skipStateNotification {
            // Normal case: Include state information
            notification["state"] = state
            notification["factoid"] = factoid
        } else if !newlyEarnedBadges.isEmpty {
            // Special case: Skip state welcome, but show badge notification
            // only if there are badges to show
            notification["state"] = state
            notification["skipWelcome"] = true
        }
        
        // Add badges if any were earned
        if !newlyEarnedBadges.isEmpty {
            notification["badges"] = newlyEarnedBadges
            
            // If there are more badges than we can reasonably display,
            // include a total count to show "and X more" text
            if newlyEarnedBadges.count > 3 {
                notification["totalBadgeCount"] = newlyEarnedBadges.count
            }
        }
        
        // Only post notification if we have something to show
        if !notification.isEmpty {
            // Post notification for real-time display
            print("🏆 Posting notification with \(newlyEarnedBadges.count) badges")
            NotificationCenter.default.post(
                name: NSNotification.Name("StateDetectionWithBadges"),
                object: nil,
                userInfo: notification
            )
        }
    }
}