import Foundation
import SwiftUI

/// Service for tracking earned badges and handling badge notifications
class BadgeTrackingService {
    private let userDefaults = UserDefaults.standard
    private let earnedBadgesKey = "earned_badges"
    private let newBadgesKey = "new_badges"
    private let viewedBadgesKey = "viewed_badges"
    
    /// Returns dictionary of badge IDs and when they were earned
    func getEarnedBadges() -> [String: Date] {
        if let data = userDefaults.data(forKey: earnedBadgesKey),
           let earnedBadges = try? JSONDecoder().decode([String: Date].self, from: data) {
            return earnedBadges
        }
        return [:]
    }
    
    private let earnedBadgeStatesKey = "earned_badge_states"

    /// Get states that were visited when each badge was earned
    func getEarnedBadgeStates() -> [String: [String]] {
        if let data = userDefaults.data(forKey: earnedBadgeStatesKey),
           let earnedBadgeStates = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return earnedBadgeStates
        }
        return [:]
    }

    /// Save newly earned badge with timestamp and the states that were visited
    func saveEarnedBadge(id: String, date: Date = Date(), visitedStates: [String] = [], hasBeenViewed: Bool = false) {
        // For badges with specific requirements, validate all states are present
        if let badge = AchievementBadgeProvider.allBadges.first(where: { $0.id == id }),
           !badge.requiredStates.isEmpty && badge.requiredStates.first != "Any" {

            let requiredStates = Set(badge.requiredStates)
            let visitedStatesSet = Set(visitedStates)

            // Double-check that all required states are present
            if !requiredStates.isSubset(of: visitedStatesSet) {
                print("🏆 Validation failed: Badge \(id) requires specific states that haven't been visited")
                return
            }
        }

        // Save badge with timestamp
        var earnedBadges = getEarnedBadges()
        let isNewBadge = earnedBadges[id] == nil
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
        
        // Check if this badge has been viewed before or if we're marking it as viewed
        let viewedBadges = getViewedBadges()
        let wasPreviouslyViewed = viewedBadges.contains(id)
        
        // Update viewed badges list if hasBeenViewed is true
        if hasBeenViewed && !wasPreviouslyViewed {
            var updatedViewedBadges = viewedBadges
            updatedViewedBadges.append(id)
            userDefaults.set(updatedViewedBadges, forKey: viewedBadgesKey)
        }
        
        // Only add to new badges if it's truly new or hasn't been viewed yet
        if (isNewBadge || !wasPreviouslyViewed) && !hasBeenViewed {
            var newBadges = getNewBadges()
            if !newBadges.contains(id) {
                newBadges.append(id)
                userDefaults.set(newBadges, forKey: newBadgesKey)
            }
        }
    }
    
    /// Get newly earned badges (not yet seen by user)
    func getNewBadges() -> [String] {
        return userDefaults.stringArray(forKey: newBadgesKey) ?? []
    }
    
    /// Clear new badges after user has seen them
    func clearNewBadges() {
        // Get current earned badges and mark them as viewed
        let currentNewBadges = getNewBadges()
        if !currentNewBadges.isEmpty {
            var viewedBadges = getViewedBadges()
            viewedBadges.append(contentsOf: currentNewBadges)
            
            // Remove duplicates
            viewedBadges = Array(Set(viewedBadges))
            
            // Save the updated viewed badges list
            userDefaults.set(viewedBadges, forKey: viewedBadgesKey)
        }
        
        // Clear the new badges list
        userDefaults.removeObject(forKey: newBadgesKey)
    }
    
    /// Get badges that have been viewed by the user
    func getViewedBadges() -> [String] {
        return userDefaults.stringArray(forKey: viewedBadgesKey) ?? []
    }
    
    // Key for storing state visit timestamps
    private let stateVisitTimestampsKey = "state_visit_timestamps"
    
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
    
    /// Check if multiple states were visited in the same calendar day
    private func checkMultipleStatesInOneDay(count: Int) -> Bool {
        let timestamps = getStateVisitTimestamps()
        
        // We need at least the required number of states with timestamps
        if timestamps.count < count {
            return false
        }
        
        // Group states by calendar day
        var statesByDay: [String: Set<String>] = [:]
        let calendar = Calendar.current
        
        for (state, date) in timestamps {
            // Get day string in format YYYY-MM-DD
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            let dayString = "\(components.year!)-\(components.month!)-\(components.day!)"
            
            // Add state to this day's set
            if statesByDay[dayString] == nil {
                statesByDay[dayString] = []
            }
            statesByDay[dayString]?.insert(state)
        }
        
        // Check if any day has at least the required number of states
        return statesByDay.values.contains { $0.count >= count }
    }
    
    /// Check if a certain number of unique states were visited within a rolling window of days
    private func checkUniqueStatesInDays(count: Int, days: Int) -> Bool {
        let timestamps = getStateVisitTimestamps()
        
        // We need at least the required number of states with timestamps
        if timestamps.count < count {
            return false
        }
        
        // Get all dates sorted
        let sortedEntries = timestamps.sorted { $0.value < $1.value }
        
        // Check rolling windows
        for i in 0..<sortedEntries.count {
            let startDate = sortedEntries[i].value
            let endDate = startDate.addingTimeInterval(TimeInterval(days * 24 * 60 * 60))
            
            // Count unique states within this window
            var statesInWindow = Set<String>()
            statesInWindow.insert(sortedEntries[i].key)
            
            // Look at all states that were visited within the window
            for j in (i+1)..<sortedEntries.count {
                if sortedEntries[j].value <= endDate {
                    statesInWindow.insert(sortedEntries[j].key)
                } else {
                    break // No need to check further as dates are sorted
                }
            }
            
            // If we found enough unique states in this window, return true
            if statesInWindow.count >= count {
                return true
            }
        }
        
        return false
    }
    
    /// Get actual badge objects for IDs
    func getBadgeObjectsForIds(_ ids: [String]) -> [AchievementBadge] {
        let allBadges = AchievementBadgeProvider.allBadges
        var result: [AchievementBadge] = []

        for id in ids {
            // Handle normal badges
            if let badge = allBadges.first(where: { $0.id == id }) {
                result.append(badge)
            }
            // Handle duplicate IDs for testing (badges with _copy_ in their ID)
            else if id.contains("_copy_") {
                // Extract the original ID from the duplicate ID
                let components = id.components(separatedBy: "_copy_")
                if components.count > 0, let originalId = components.first,
                   let originalBadge = allBadges.first(where: { $0.id == originalId }) {
                    // Create a badge copy with the new ID
                    // This is a hack for testing only
                    result.append(AchievementBadge(
                        id: id,
                        name: originalBadge.name,
                        description: originalBadge.description,
                        requiredStates: originalBadge.requiredStates,
                        specialCondition: originalBadge.specialCondition,
                        category: originalBadge.category
                    ))
                }
            }
        }

        return result
    }
    
    /// Check for newly earned badges based on states
    func checkForNewBadges(allBadges: [AchievementBadge], visitedStates: [String]) -> [AchievementBadge] {
        // Get currently earned badges to avoid duplicates
        let earnedBadges = getEarnedBadges()
        var newlyEarnedBadges: [AchievementBadge] = []

        // Filter out District of Columbia for badge calculations
        let filteredStates = visitedStates.filter { $0 != "District of Columbia" }

        // Iterate through each badge to check requirements
        for badge in allBadges {
            // Skip badges that are already earned
            if earnedBadges[badge.id] != nil {
                continue
            }

            // Check if badge requirements are met
            if isBadgeRequirementsMet(badge, visitedStates: filteredStates) {
                // For badges with specific state requirements, save which states contributed
                var statesToSave: [String] = []

                if !badge.requiredStates.isEmpty && badge.requiredStates.first != "Any" {
                    // For specific state requirement badges, save the intersection of required and visited states
                    let requiredStatesSet = Set(badge.requiredStates)
                    let visitedStatesSet = Set(filteredStates)
                    statesToSave = Array(requiredStatesSet.intersection(visitedStatesSet)).sorted()
                } else if badge.category == .milestone {
                    // For milestone badges, save all states that contributed
                    statesToSave = filteredStates
                }

                // Save the badge as earned with current timestamp and contributing states
                saveEarnedBadge(id: badge.id, date: Date(), visitedStates: statesToSave)
                newlyEarnedBadges.append(badge)
            }
        }

        return newlyEarnedBadges
    }
    
    /// Logic to check if badge requirements are met
    func isBadgeRequirementsMet(_ badge: AchievementBadge, visitedStates: [String]) -> Bool {
        // Filter out District of Columbia for badge calculations
        let filteredStates = visitedStates.filter { $0 != "District of Columbia" }

        // For milestone badges
        if badge.category == .milestone && badge.requiredStates.first == "Any" {
            switch badge.id {
            case "newbie": return filteredStates.count >= 1
            case "explorer": return filteredStates.count >= 10
            case "journeyer": return filteredStates.count >= 20
            case "voyager": return filteredStates.count >= 30
            case "adventurer": return filteredStates.count >= 40
            case "completionist": return filteredStates.count >= 50
            default: return false
            }
        }

        // For badges with specific state requirements
        if !badge.requiredStates.isEmpty {
            let requiredStatesSet = Set(badge.requiredStates)
            let visitedStatesSet = Set(filteredStates)

            // Check if ALL required states have been visited
            return requiredStatesSet.isSubset(of: visitedStatesSet)
        }

        // For special condition badges
        if let condition = badge.specialCondition {
            switch condition {
            case .multipleStatesInOneDay(let count):
                // Use our new timestamp tracking logic
                return checkMultipleStatesInOneDay(count: count)
            case .uniqueStatesInDays(let count, let days):
                // Check for unique states visited within a rolling window
                return checkUniqueStatesInDays(count: count, days: days)
            case .sameCalendarYear(_):
                // Not implemented yet - future enhancement
                return false
            case .returningVisit(_, _):
                // Not implemented yet - future enhancement
                return false
            case .directionStates(let direction):
                // Check if all directional states are visited
                if direction == "N" {
                    let northStates = ["North Dakota", "North Carolina"]
                    return Set(northStates).isSubset(of: Set(visitedStates))
                } else if direction == "S" {
                    let southStates = ["South Dakota", "South Carolina"]
                    return Set(southStates).isSubset(of: Set(visitedStates))
                } else if direction == "W" {
                    return visitedStates.contains("West Virginia")
                } else {
                    return false
                }
            }
        }

        return false
    }

    /// Calculate progress toward a badge (0.0 - 1.0)
    func calculateBadgeProgress(_ badge: AchievementBadge, visitedStates: [String]) -> Float {
        // If badge is already earned, progress is 100%
        if getEarnedBadges()[badge.id] != nil {
            return 1.0
        }

        // Filter out District of Columbia for badge calculations
        let filteredStates = visitedStates.filter { $0 != "District of Columbia" }

        // For milestone badges - calculate based on state count
        if badge.category == .milestone && badge.requiredStates.first == "Any" {
            switch badge.id {
            case "newbie":
                return filteredStates.isEmpty ? 0.0 : 1.0
            case "explorer":
                return min(Float(filteredStates.count) / 10.0, 1.0)
            case "journeyer":
                return min(Float(filteredStates.count) / 20.0, 1.0)
            case "voyager":
                return min(Float(filteredStates.count) / 30.0, 1.0)
            case "adventurer":
                return min(Float(filteredStates.count) / 40.0, 1.0)
            case "completionist":
                return min(Float(filteredStates.count) / 50.0, 1.0)
            default:
                return 0.0
            }
        }

        // For badges with specific state requirements
        if !badge.requiredStates.isEmpty {
            let requiredStatesSet = Set(badge.requiredStates)
            let visitedStatesSet = Set(filteredStates)
            let matchingStates = requiredStatesSet.intersection(visitedStatesSet)

            return Float(matchingStates.count) / Float(requiredStatesSet.count)
        }

        // For special condition badges - we can't easily compute progress
        if badge.specialCondition != nil {
            // For now, return 0 if not earned, can enhance later
            return 0.0
        }

        return 0.0
    }

    /// Get list of states that user has visited toward a badge
    func getVisitedStatesForBadge(_ badge: AchievementBadge, visitedStates: [String]) -> [String] {
        // Check if this badge has been earned
        let earnedBadges = getEarnedBadges()

        // If the badge has been earned, return the states that were saved when it was earned
        if earnedBadges[badge.id] != nil {
            let earnedBadgeStates = getEarnedBadgeStates()
            if let statesWhenEarned = earnedBadgeStates[badge.id], !statesWhenEarned.isEmpty {
                return statesWhenEarned
            }

            // If we don't have saved states for an earned badge (prior to this update),
            // use current state data but still show it as fully earned
            if badge.category == .milestone && badge.requiredStates.first == "Any" {
                return []
            } else if !badge.requiredStates.isEmpty {
                // For old earned badges without saved states, show all the required states
                return badge.requiredStates.sorted()
            }
        }

        // Not earned yet or old badge without proper state tracking
        // Filter out District of Columbia for badge calculations
        let filteredStates = visitedStates.filter { $0 != "District of Columbia" }

        // For milestone badges, this doesn't apply (no specific states)
        if badge.category == .milestone && badge.requiredStates.first == "Any" {
            return []
        }

        // For badges with specific state requirements
        if !badge.requiredStates.isEmpty {
            let requiredStatesSet = Set(badge.requiredStates)
            let visitedStatesSet = Set(filteredStates)
            let matchingStates = requiredStatesSet.intersection(visitedStatesSet)
            return Array(matchingStates).sorted()
        }

        return []
    }

    /// Get list of states still needed for a badge
    func getNeededStatesForBadge(_ badge: AchievementBadge, visitedStates: [String]) -> [String] {
        // If badge is already earned, no states needed
        if getEarnedBadges()[badge.id] != nil {
            return []
        }

        // Filter out District of Columbia for badge calculations
        let filteredStates = visitedStates.filter { $0 != "District of Columbia" }

        // For milestone badges
        if badge.category == .milestone && badge.requiredStates.first == "Any" {
            let statesNeeded: Int
            switch badge.id {
            case "newbie": statesNeeded = 1
            case "explorer": statesNeeded = 10
            case "journeyer": statesNeeded = 20
            case "voyager": statesNeeded = 30
            case "adventurer": statesNeeded = 40
            case "completionist": statesNeeded = 50
            default: statesNeeded = 0
            }

            let remaining = max(0, statesNeeded - filteredStates.count)
            if remaining > 0 {
                return ["Need \(remaining) more states"]
            } else {
                return []
            }
        }

        // For badges with specific state requirements
        if !badge.requiredStates.isEmpty {
            let requiredStatesSet = Set(badge.requiredStates)
            let visitedStatesSet = Set(filteredStates)
            let neededStates = requiredStatesSet.subtracting(visitedStatesSet)
            return Array(neededStates).sorted()
        }

        // For special condition badges
        if let condition = badge.specialCondition {
            switch condition {
            case .multipleStatesInOneDay(let count):
                return ["Visit \(count) states in one day"]
            case .uniqueStatesInDays(let count, let days):
                return ["Visit \(count) unique states within \(days) days"]
            case .sameCalendarYear(let count):
                return ["Visit \(count) states in one calendar year"]
            case .returningVisit(let state, let daysBetween):
                return ["Revisit \(state) after \(daysBetween) days"]
            case .directionStates(let direction):
                if direction == "N" {
                    let northStates = ["North Dakota", "North Carolina"]
                    let neededStates = Set(northStates).subtracting(Set(visitedStates))
                    return Array(neededStates).sorted()
                } else if direction == "S" {
                    let southStates = ["South Dakota", "South Carolina"]
                    let neededStates = Set(southStates).subtracting(Set(visitedStates))
                    return Array(neededStates).sorted()
                } else if direction == "W" {
                    return visitedStates.contains("West Virginia") ? [] : ["West Virginia"]
                } else {
                    return []
                }
            }
        }

        return []
    }
    
    /// Clear all earned badges (for testing)
    func resetAllBadges() {
        userDefaults.removeObject(forKey: earnedBadgesKey)
        userDefaults.removeObject(forKey: newBadgesKey)
        userDefaults.removeObject(forKey: earnedBadgeStatesKey)
        userDefaults.removeObject(forKey: viewedBadgesKey)
    }
}