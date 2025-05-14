import Foundation
import SwiftUI

// Simple utility to inspect badge data in UserDefaults
// Run this with: swift inspect_badges.swift

// Get the UserDefaults
let userDefaults = UserDefaults.standard

// Function to retrieve earned badges
func getEarnedBadges() -> [String: Date] {
    let earnedBadgesKey = "earned_badges"
    if let data = userDefaults.data(forKey: earnedBadgesKey),
       let earnedBadges = try? JSONDecoder().decode([String: Date].self, from: data) {
        return earnedBadges
    }
    return [:]
}

// Function to retrieve new badges
func getNewBadges() -> [String] {
    let newBadgesKey = "new_badges"
    return userDefaults.stringArray(forKey: newBadgesKey) ?? []
}

// Main inspection
print("=== BADGE INSPECTION ===")
print("UserDefaults.standard contains:")

// Check if earned_badges exists
if userDefaults.object(forKey: "earned_badges") != nil {
    print("✓ 'earned_badges' key exists")
    
    // Get and display earned badges
    let earnedBadges = getEarnedBadges()
    print("📊 Total earned badges: \(earnedBadges.count)")
    
    // Print details about each earned badge
    print("\nEarned Badges List:")
    print("-------------------")
    for (badgeId, date) in earnedBadges.sorted(by: { $0.value < $1.value }) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        print("🏆 \(badgeId): earned on \(dateFormatter.string(from: date))")
    }
} else {
    print("❌ 'earned_badges' key does not exist")
}

// Check for new badges
if let newBadges = userDefaults.stringArray(forKey: "new_badges") {
    print("\n📊 New badges count: \(newBadges.count)")
    print("New badges: \(newBadges.joined(separator: ", "))")
} else {
    print("\n❌ 'new_badges' key does not exist or is empty")
}

// Check for badge states
if userDefaults.object(forKey: "earned_badge_states") != nil {
    print("\n✓ 'earned_badge_states' key exists")
    // Try to decode the badge states
    if let data = userDefaults.data(forKey: "earned_badge_states"),
       let badgeStates = try? JSONDecoder().decode([String: [String]].self, from: data) {
        print("📊 Badge states tracked for \(badgeStates.count) badges")
        
        // Print details about each badge's states
        print("\nBadge States List:")
        print("-----------------")
        for (badgeId, states) in badgeStates.sorted(by: { $0.key < $1.key }) {
            print("🏆 \(badgeId): \(states.joined(separator: ", "))")
        }
    } else {
        print("❌ 'earned_badge_states' key exists but couldn't be decoded")
    }
} else {
    print("\n❌ 'earned_badge_states' key does not exist")
}

print("\n===== END OF REPORT =====")