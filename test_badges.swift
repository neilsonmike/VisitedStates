#!/usr/bin/env swift

import Foundation

// A simple script to test badge earning
print("\n✨ Badge Testing Tool ✨")
print("======================\n")

// Access the BadgeTrackingService functions
class BadgeTrackingService {
    private let userDefaults = UserDefaults.standard
    private let earnedBadgesKey = "earned_badges"
    private let newBadgesKey = "new_badges"
    private let earnedBadgeStatesKey = "earned_badge_states"
    
    /// Returns dictionary of badge IDs and when they were earned
    func getEarnedBadges() -> [String: Date] {
        if let data = userDefaults.data(forKey: earnedBadgesKey),
           let earnedBadges = try? JSONDecoder().decode([String: Date].self, from: data) {
            return earnedBadges
        }
        return [:]
    }
    
    /// Get states that were visited when each badge was earned
    func getEarnedBadgeStates() -> [String: [String]] {
        if let data = userDefaults.data(forKey: earnedBadgeStatesKey),
           let earnedBadgeStates = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return earnedBadgeStates
        }
        return [:]
    }

    /// Save newly earned badge with timestamp and the states that were visited
    func saveEarnedBadge(id: String, date: Date = Date(), visitedStates: [String] = []) {
        print("Saving badge: \(id) with \(visitedStates.count) states")
        
        // Save badge with timestamp
        var earnedBadges = getEarnedBadges()
        earnedBadges[id] = date

        if let encoded = try? JSONEncoder().encode(earnedBadges) {
            userDefaults.set(encoded, forKey: earnedBadgesKey)
        }

        // Save the states that contributed to earning this badge
        var earnedBadgeStates = getEarnedBadgeStates()
        earnedBadgeStates[id] = visitedStates

        if let encoded = try? JSONEncoder().encode(earnedBadgeStates) {
            userDefaults.set(encoded, forKey: earnedBadgeStatesKey)
        }

        // Add to new badges list
        var newBadges = getNewBadges()
        if !newBadges.contains(id) {
            newBadges.append(id)
            userDefaults.set(newBadges, forKey: newBadgesKey)
        }
        
        print("Badge \(id) saved successfully")
    }
    
    /// Get newly earned badges (not yet seen by user)
    func getNewBadges() -> [String] {
        return userDefaults.stringArray(forKey: newBadgesKey) ?? []
    }
    
    /// Track state visit with current timestamp
    func trackStateVisit(_ state: String) {
        // Get existing timestamps
        var timestampsByState = getStateVisitTimestamps()
        
        // Add current timestamp for this state
        let now = Date()
        timestampsByState[state] = now
        
        // Save updated timestamps
        if let encoded = try? JSONEncoder().encode(timestampsByState) {
            userDefaults.set(encoded, forKey: stateVisitTimestampsKey)
        }
    }
    
    /// Get dictionary of states and when they were last visited
    private func getStateVisitTimestamps() -> [String: Date] {
        if let data = userDefaults.data(forKey: stateVisitTimestampsKey),
           let timestamps = try? JSONDecoder().decode([String: Date].self, from: data) {
            return timestamps
        }
        return [:]
    }
    
    /// Clear all earned badges (for testing)
    func resetAllBadges() {
        userDefaults.removeObject(forKey: earnedBadgesKey)
        userDefaults.removeObject(forKey: newBadgesKey)
        userDefaults.removeObject(forKey: earnedBadgeStatesKey)
        print("All badges reset")
    }
    
    // Key for storing state visit timestamps
    private let stateVisitTimestampsKey = "state_visit_timestamps"
}

// Function to check current badge state
func checkBadgeStatus() {
    let badgeService = BadgeTrackingService()
    
    let earnedBadges = badgeService.getEarnedBadges()
    let earnedBadgeStates = badgeService.getEarnedBadgeStates()
    let newBadges = badgeService.getNewBadges()
    
    print("\n===== CURRENT BADGE STATUS =====")
    print("Earned Badges: \(earnedBadges.count)")
    print("Badge States: \(earnedBadgeStates.count)")
    print("New Badges: \(newBadges.count)")
    
    if !earnedBadges.isEmpty {
        print("\nEarned Badge Details:")
        for (id, date) in earnedBadges {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let statesText = earnedBadgeStates[id]?.joined(separator: ", ") ?? "none"
            print("- \(id): Earned on \(formatter.string(from: date))")
            print("  States: \(statesText)")
        }
    }
}

// Options menu
func showMenu() {
    print("\nOptions:")
    print("1. Check current badge status")
    print("2. Reset all badges")
    print("3. Award milestone badges")
    print("4. Award Four Corners Explorer badge")
    print("5. Award Pacific Wanderer badge")
    print("6. Award On the Road Again badge")
    print("7. Award Border Patrol North badge")
    print("8. Exit")
    print("\nChoice: ", terminator: "")
}

// Main program loop
func main() {
    checkBadgeStatus()
    
    var running = true
    let badgeService = BadgeTrackingService()
    
    while running {
        showMenu()
        
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            continue
        }
        
        switch input {
        case "1":
            checkBadgeStatus()
            
        case "2":
            badgeService.resetAllBadges()
            print("All badges have been reset")
            
        case "3":
            print("Awarding milestone badges...")
            
            // Newbie badge (1 state)
            badgeService.saveEarnedBadge(id: "newbie", visitedStates: ["California"])
            
            // Explorer badge (10 states)
            let states10 = ["California", "Oregon", "Washington", "Idaho", "Nevada", 
                         "Arizona", "Utah", "Montana", "Wyoming", "Colorado"]
            badgeService.saveEarnedBadge(id: "explorer", visitedStates: states10)
            
            // Track state visits for these states
            for state in states10 {
                badgeService.trackStateVisit(state)
            }
            
            print("Milestone badges awarded")
            
        case "4":
            // Four Corners Explorer badge
            let fourCorners = ["Arizona", "Colorado", "New Mexico", "Utah"]
            badgeService.saveEarnedBadge(id: "four_corners", visitedStates: fourCorners)
            
            // Track state visits
            for state in fourCorners {
                badgeService.trackStateVisit(state)
            }
            
            print("Four Corners Explorer badge awarded")
            
        case "5":
            // Pacific Wanderer badge
            let pacificStates = ["California", "Oregon", "Washington", "Alaska", "Hawaii"]
            badgeService.saveEarnedBadge(id: "pacific_wanderer", visitedStates: pacificStates)
            
            // Track state visits
            for state in pacificStates {
                badgeService.trackStateVisit(state)
            }
            
            print("Pacific Wanderer badge awarded")
            
        case "6":
            // On the Road Again badge (3 states in one day)
            // We'll need to track the visits with same timestamp
            let roadTripStates = ["Pennsylvania", "Ohio", "Indiana"]
            
            // Track state visits with same timestamp
            for state in roadTripStates {
                badgeService.trackStateVisit(state)
            }
            
            badgeService.saveEarnedBadge(id: "on_the_road", visitedStates: roadTripStates)
            print("On the Road Again badge awarded")
            
        case "7":
            // Border Patrol North badge
            let northernStates = ["Alaska", "Idaho", "Maine", "Michigan", "Minnesota",
                               "Montana", "New Hampshire", "New York", "North Dakota",
                               "Vermont", "Washington"]
            badgeService.saveEarnedBadge(id: "border_patrol_north", visitedStates: northernStates)
            
            // Track state visits
            for state in northernStates {
                badgeService.trackStateVisit(state)
            }
            
            print("Border Patrol North badge awarded")
            
        case "8":
            running = false
            print("Exiting...")
            
        default:
            print("Invalid option")
        }
    }
}

// Convert to CloudKit badge format
func convertToCloudKitBadges() {
    let badgeService = BadgeTrackingService()
    let earnedBadges = badgeService.getEarnedBadges()
    
    print("\n===== CONVERTING TO CLOUDKIT FORMAT =====")
    
    // Convert to CloudKit badge format
    var cloudKitBadges: [[String: Any]] = []
    
    for (id, date) in earnedBadges {
        let badge: [String: Any] = [
            "identifier": id,
            "isEarned": true,
            "earnedDate": date
        ]
        cloudKitBadges.append(badge)
    }
    
    // Convert to JSON
    if let jsonData = try? JSONSerialization.data(withJSONObject: cloudKitBadges),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print("CloudKit badge JSON:")
        print(jsonString)
        
        // Save to UserDefaults for debugging
        UserDefaults.standard.set(jsonString, forKey: "badgesJSON")
    } else {
        print("Failed to convert badges to JSON")
    }
}

// Run the main program
main()
// Convert earned badges to CloudKit format after running the program
convertToCloudKitBadges()