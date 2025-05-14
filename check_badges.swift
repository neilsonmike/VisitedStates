#!/usr/bin/env swift

import Foundation

// A simple script to check badge data in UserDefaults
let userDefaults = UserDefaults.standard

// Print the app's bundle ID if we can find it
print("Checking UserDefaults for badge data...")
let possibleBundleIds = [
    "com.neils.visited-states",
    "com.neils.VisitedStates"
]

for bundleId in possibleBundleIds {
    print("\nChecking domain: \(bundleId)")
    
    if let domain = UserDefaults.standard.persistentDomain(forName: bundleId) {
        print("Found persistent domain with \(domain.count) keys")
        
        // Check if our badge keys exist in this domain
        let badgeKeys = ["earned_badges", "earned_badge_states", "new_badges"]
        for key in badgeKeys {
            print("  - \(key): \(domain[key] != nil ? "exists" : "not found")")
        }
    } else {
        print("No persistent domain found for \(bundleId)")
    }
}

// Keys used by BadgeTrackingService
let earnedBadgesKey = "earned_badges"
let earnedBadgeStatesKey = "earned_badge_states"
let newBadgesKey = "new_badges"

// Check earned badges (dictionary of badge IDs and when they were earned)
if let data = userDefaults.data(forKey: earnedBadgesKey) {
    do {
        if let earnedBadges = try? JSONDecoder().decode([String: Date].self, from: data) {
            print("\n===== EARNED BADGES =====")
            print("Count: \(earnedBadges.count)")
            
            if earnedBadges.isEmpty {
                print("No earned badges found")
            } else {
                print("\nBADGE LIST:")
                for (id, date) in earnedBadges.sorted(by: { $0.key < $1.key }) {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    print("Badge: \(id), Earned: \(formatter.string(from: date))")
                }
            }
        } else {
            print("Failed to decode earnedBadges data")
            print("Raw data: \(String(data: data, encoding: .utf8) ?? "unreadable")")
        }
    } catch {
        print("Error decoding earnedBadges: \(error)")
    }
} else {
    print("\n===== EARNED BADGES =====")
    print("No earnedBadges data found in UserDefaults")
}

// Check earned badge states (which states contributed to earning each badge)
if let data = userDefaults.data(forKey: earnedBadgeStatesKey) {
    do {
        if let earnedBadgeStates = try? JSONDecoder().decode([String: [String]].self, from: data) {
            print("\n===== EARNED BADGE STATES =====")
            print("Count: \(earnedBadgeStates.count)")
            
            if earnedBadgeStates.isEmpty {
                print("No earned badge states found")
            } else {
                print("\nBADGE STATES:")
                for (id, states) in earnedBadgeStates.sorted(by: { $0.key < $1.key }) {
                    print("Badge: \(id), States: \(states.joined(separator: ", "))")
                }
            }
        } else {
            print("Failed to decode earnedBadgeStates data")
            print("Raw data: \(String(data: data, encoding: .utf8) ?? "unreadable")")
        }
    } catch {
        print("Error decoding earnedBadgeStates: \(error)")
    }
} else {
    print("\n===== EARNED BADGE STATES =====")
    print("No earnedBadgeStates data found in UserDefaults")
}

// Check new badges (not yet seen by user)
if let newBadges = userDefaults.stringArray(forKey: newBadgesKey) {
    print("\n===== NEW BADGES =====")
    print("Count: \(newBadges.count)")
    
    if newBadges.isEmpty {
        print("No new badges found")
    } else {
        print("\nNEW BADGE LIST:")
        for id in newBadges.sorted() {
            print("Badge: \(id)")
        }
    }
} else {
    print("\n===== NEW BADGES =====")
    print("No newBadges data found in UserDefaults")
}

// Check CloudKit badge data in UserDefaults
let badgesJSONKey = "badgesJSON"
if let badgesJSON = userDefaults.string(forKey: badgesJSONKey) {
    print("\n===== CLOUDKIT BADGES JSON =====")
    print("Raw data: \(badgesJSON)")
    
    if let data = badgesJSON.data(using: .utf8) {
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            print("Parsed JSON: \(json)")
        } catch {
            print("Error parsing badgesJSON: \(error)")
        }
    }
} else {
    print("\n===== CLOUDKIT BADGES JSON =====")
    print("No badgesJSON data found in UserDefaults")
}

// Check state visit timestamps
let stateVisitTimestampsKey = "state_visit_timestamps"
if let data = userDefaults.data(forKey: stateVisitTimestampsKey) {
    do {
        if let timestamps = try? JSONDecoder().decode([String: Date].self, from: data) {
            print("\n===== STATE VISIT TIMESTAMPS =====")
            print("Count: \(timestamps.count)")
            
            if timestamps.isEmpty {
                print("No state visit timestamps found")
            } else {
                print("\nSTATE VISIT TIMESTAMPS:")
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                
                for (state, date) in timestamps.sorted(by: { $0.key < $1.key }) {
                    print("State: \(state), Visited: \(formatter.string(from: date))")
                }
            }
        } else {
            print("Failed to decode state visit timestamps data")
            print("Raw data: \(String(data: data, encoding: .utf8) ?? "unreadable")")
        }
    } catch {
        print("Error decoding state visit timestamps: \(error)")
    }
} else {
    print("\n===== STATE VISIT TIMESTAMPS =====")
    print("No state visit timestamps found in UserDefaults")
}

// Print all UserDefaults keys for debugging
print("\n===== ALL USERDEFAULTS KEYS =====")
if let appDomain = Bundle.main.bundleIdentifier,
   let dict = UserDefaults.standard.persistentDomain(forName: appDomain) {
    let keys = Array(dict.keys).sorted()
    print("Found \(keys.count) keys:")
    for key in keys {
        print("- \(key)")
    }
} else {
    // This approach might work when running outside the app bundle
    print("Using fallback approach to list UserDefaults:")
    let keys = [
        "earned_badges",
        "earned_badge_states",
        "new_badges",
        "state_visit_timestamps",
        "badgesJSON",
        "visitedStatesJSON",
        "visitedStatesString",
        "notificationsEnabled",
        "notifyOnlyNewStates",
        "speedThreshold",
        "altitudeThreshold",
        "lastVisitedState"
    ]
    
    for key in keys {
        let exists = UserDefaults.standard.object(forKey: key) != nil
        print("- \(key): \(exists ? "exists" : "not found")")
    }
}