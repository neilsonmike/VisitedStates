import Foundation
import SwiftUI

/// Represents a collectible badge in the app
struct AchievementBadge: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let requiredStates: [String]
    let specialCondition: AchievementBadgeCondition?
    let category: AchievementBadgeCategory
    
    /// The color for the badge background
    var color: Color {
        // Individual colors for each badge
        switch id {
        // Milestone badges
        case "newbie":
            return Color(red: 0.4, green: 0.2, blue: 0.6) // Purple for first badge
        case "explorer", "journeyer", "voyager", "adventurer":
            return Color(red: 0.2, green: 0.6, blue: 0.3) // Green for progress badges
        case "completionist":
            return Color(red: 0.8, green: 0.7, blue: 0.0) // Gold for final badge
            
        // Geographic badges with custom colors
        case "four_corners":
            return Color(red: 0.8, green: 0.2, blue: 0.2) // Red
        case "pacific_wanderer":
            return Color(red: 0.9, green: 0.5, blue: 0.1) // Orange
        case "mississippi_river":
            return Color(red: 0.1, green: 0.6, blue: 0.6) // Blueish green
        case "rocky_mountain":
            return Color(red: 0.5, green: 0.2, blue: 0.7) // Purple
        case "colonist":
            return Color(red: 0.8, green: 0.2, blue: 0.2) // Red
            
        // Special badges with custom colors
        case "on_the_road":
            return Color(red: 0.2, green: 0.7, blue: 0.3) // Green
        case "border_patrol_north":
            return Color(red: 0.1, green: 0.2, blue: 0.7) // Dark blue
        case "far_reaches":
            return Color(red: 0.9, green: 0.8, blue: 0.2) // Yellow
        case "four_letter_words":
            return Color(red: 0.6, green: 0.4, blue: 0.2) // Brown
        case "directionally_impaired":
            return Color(red: 0.6, green: 0.7, blue: 0.2) // Greenish yellow
        case "new_to_you":
            return Color(red: 0.2, green: 0.7, blue: 0.3) // Green
            
        // Default colors for remaining badges by category
        default:
            switch category {
            case .milestone:
                return Color(red: 0.4, green: 0.2, blue: 0.6) // Purple default for milestone
            case .geographic:
                return Color(red: 0.2, green: 0.5, blue: 0.8) // Blue default for geographic
            case .special:
                return Color(red: 0.8, green: 0.4, blue: 0.2) // Orange default for special
            }
        }
    }
    
    /// Name of the SF Symbol to use for this badge
    var iconName: String {
        // For milestone badges, use number-based SF Symbols
        if category == .milestone {
            switch id {
            case "newbie":
                return "1.circle.fill" // Number 1 for first state
            case "explorer":
                return "10.circle.fill" // Number 10
            case "journeyer":
                return "20.circle.fill" // Number 20
            case "voyager":
                return "30.circle.fill" // Number 30
            case "adventurer":
                return "40.circle.fill" // Number 40
            case "completionist":
                return "50.circle.fill" // Number 50
            default:
                return "star.fill" // Fallback
            }
        } else if category == .geographic {
            // Geographic collection badges
            switch id {
            case "four_corners":
                return "square.grid.2x2.fill" // Four corners badge
            case "atlantic_coast":
                return "water.waves" // Waves for Atlantic coast
            case "pacific_wanderer":
                return "figure.surfing" // Surfing figure for Pacific coast
            case "gulf_coaster":
                return "tropicalstorm" // Storm icon for Gulf coast
            case "mississippi_river":
                return "ferry.fill" // Ferry for Mississippi River
            case "great_lakes":
                return "sailboat.fill" // Sailboat for Great Lakes
            case "rocky_mountain":
                return "mountain.2.fill" // Mountains
            case "colonist":
                return "star.square.fill" // Represents the original 13 colonies star
            default:
                return "map.fill" // Default map
            }
        } else {
            // Special achievement badges
            switch id {
            case "on_the_road":
                return "road.lanes" // Road
            case "border_patrol_north":
                return "snowflake" // Snowflake for northern states
            case "border_patrol_south":
                return "sun.max" // Sun for southern border states
            case "far_reaches":
                return "airplane" // Travel to Alaska and Hawaii
            case "four_letter_words":
                // We'll use custom text instead of an icon for this one
                return "" // Empty string indicates we'll use custom text
            case "directionally_impaired":
                return "safari.fill" // Safari compass icon
            case "new_to_you":
                return "tag.fill" // New tag
            case "wealth_is_common":
                return "centsign" // Cent sign for Commonwealth
            default:
                return "trophy.fill" // Default trophy
            }
        }
    }
    
    // MARK: - Equatable implementation
    static func == (lhs: AchievementBadge, rhs: AchievementBadge) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Categories of badges
enum AchievementBadgeCategory: String, CaseIterable {
    case milestone = "Milestone"
    case geographic = "Geographic Collection"
    case special = "Special Achievement"
}

/// Special conditions for badges beyond just visiting states
enum AchievementBadgeCondition: Equatable {
    case multipleStatesInOneDay(count: Int)
    case sameCalendarYear(count: Int)
    case returningVisit(state: String, daysBetween: Int)
    case directionStates(direction: String)
    // Add more special conditions as needed

    // MARK: - Equatable implementation
    static func == (lhs: AchievementBadgeCondition, rhs: AchievementBadgeCondition) -> Bool {
        switch (lhs, rhs) {
        case (.multipleStatesInOneDay(let count1), .multipleStatesInOneDay(let count2)):
            return count1 == count2
        case (.sameCalendarYear(let count1), .sameCalendarYear(let count2)):
            return count1 == count2
        case (.returningVisit(let state1, let days1), .returningVisit(let state2, let days2)):
            return state1 == state2 && days1 == days2
        case (.directionStates(let dir1), .directionStates(let dir2)):
            return dir1 == dir2
        default:
            return false
        }
    }
}

// MARK: - Hardcoded Badge Data for Prototype

/// Provides sample badge data for the prototype
class AchievementBadgeProvider {
    static var allBadges: [AchievementBadge] = [
        // Milestone Badges
        AchievementBadge(id: "newbie", name: "Newbie", description: "Visit your first state",
              requiredStates: ["Any"], specialCondition: nil, category: .milestone),
        AchievementBadge(id: "explorer", name: "Explorer", description: "Visit 10 states",
              requiredStates: ["Any"], specialCondition: nil, category: .milestone),
        AchievementBadge(id: "journeyer", name: "Journeyer", description: "Visit 20 states",
              requiredStates: ["Any"], specialCondition: nil, category: .milestone),
        AchievementBadge(id: "voyager", name: "Voyager", description: "Visit 30 states",
              requiredStates: ["Any"], specialCondition: nil, category: .milestone),
        AchievementBadge(id: "adventurer", name: "Adventurer", description: "Visit 40 states",
              requiredStates: ["Any"], specialCondition: nil, category: .milestone),
        AchievementBadge(id: "completionist", name: "Completionist", description: "Visit all 50 states",
              requiredStates: ["Any"], specialCondition: nil, category: .milestone),

        // Geographic Collection Badges
        AchievementBadge(id: "four_corners", name: "Four Corners Explorer",
              description: "Visit all four Four Corners states",
              requiredStates: ["Arizona", "Colorado", "New Mexico", "Utah"],
              specialCondition: nil, category: .geographic),
        AchievementBadge(id: "atlantic_coast", name: "Atlantic Coaster",
              description: "Visit all states bordering the Atlantic Ocean",
              requiredStates: ["Connecticut", "Delaware", "Florida", "Georgia", "Maine", "Maryland",
                               "Massachusetts", "New Hampshire", "New Jersey", "New York", "North Carolina",
                               "Rhode Island", "South Carolina", "Virginia"],
              specialCondition: nil, category: .geographic),
        AchievementBadge(id: "pacific_wanderer", name: "Pacific Wanderer",
              description: "Visit all states bordering the Pacific Ocean",
              requiredStates: ["California", "Oregon", "Washington", "Alaska", "Hawaii"],
              specialCondition: nil, category: .geographic),
        AchievementBadge(id: "gulf_coaster", name: "Gulf Coaster",
              description: "Visit all states bordering the Gulf of Mexico",
              requiredStates: ["Alabama", "Florida", "Louisiana", "Mississippi", "Texas"],
              specialCondition: nil, category: .geographic),
        AchievementBadge(id: "mississippi_river", name: "Mississippi River Runner",
              description: "Visit all states bordering the Mississippi River",
              requiredStates: ["Arkansas", "Illinois", "Iowa", "Kentucky", "Louisiana",
                               "Minnesota", "Mississippi", "Missouri", "Tennessee", "Wisconsin"],
              specialCondition: nil, category: .geographic),
        AchievementBadge(id: "great_lakes", name: "Great Lakes Explorer",
              description: "Visit all states bordering the Great Lakes",
              requiredStates: ["Illinois", "Indiana", "Michigan", "Minnesota",
                               "New York", "Ohio", "Pennsylvania", "Wisconsin"],
              specialCondition: nil, category: .geographic),
        AchievementBadge(id: "rocky_mountain", name: "Rocky Mountain High",
              description: "Visit all states in the Rocky Mountain region",
              requiredStates: ["Colorado", "Idaho", "Montana", "Nevada", "Utah", "Wyoming"],
              specialCondition: nil, category: .geographic),
        AchievementBadge(id: "colonist", name: "Colonist",
              description: "Visit all 13 original colonies",
              requiredStates: ["Connecticut", "Delaware", "Georgia", "Maryland", "Massachusetts",
                               "New Hampshire", "New Jersey", "New York", "North Carolina",
                               "Pennsylvania", "Rhode Island", "South Carolina", "Virginia"],
              specialCondition: nil, category: .geographic),

        // Special Achievement Badges
        AchievementBadge(id: "on_the_road", name: "On the Road Again",
              description: "Visit 3 or more states in a single calendar day",
              requiredStates: [],
              specialCondition: .multipleStatesInOneDay(count: 3), category: .special),
        AchievementBadge(id: "border_patrol_north", name: "Border Patrol North",
              description: "Visit all states bordering Canada",
              requiredStates: ["Alaska", "Idaho", "Maine", "Michigan", "Minnesota",
                               "Montana", "New Hampshire", "New York", "North Dakota",
                               "Vermont", "Washington"],
              specialCondition: nil, category: .special),
        AchievementBadge(id: "border_patrol_south", name: "Border Patrol South",
              description: "Visit all states bordering Mexico",
              requiredStates: ["Arizona", "California", "New Mexico", "Texas"],
              specialCondition: nil, category: .special),
        AchievementBadge(id: "far_reaches", name: "Far Reaches",
              description: "Visit both Alaska and Hawaii",
              requiredStates: ["Alaska", "Hawaii"],
              specialCondition: nil, category: .special),
        AchievementBadge(id: "four_letter_words", name: "Four Letter Words",
              description: "Visit all states with 4-letter names",
              requiredStates: ["Utah", "Ohio", "Iowa"],
              specialCondition: nil, category: .special),
        AchievementBadge(id: "directionally_impaired", name: "Directionally Impaired",
              description: "Visit all directional states (North, South, West, East)",
              requiredStates: ["North Carolina", "North Dakota", "South Carolina", "South Dakota",
                               "West Virginia"],
              specialCondition: nil, category: .special),
        AchievementBadge(id: "new_to_you", name: "New to You",
              description: "Visit all states with 'New' in their name",
              requiredStates: ["New Hampshire", "New Jersey", "New Mexico", "New York"],
              specialCondition: nil, category: .special),
        AchievementBadge(id: "wealth_is_common", name: "The Wealth is Common",
              description: "Visit all four states that are legally commonwealths",
              requiredStates: ["Virginia", "Pennsylvania", "Kentucky", "Massachusetts"],
              specialCondition: nil, category: .special)
    ]
    
    /// Get samples of badges with different earned states for UI testing
    static func getSampleBadgeData() -> [(AchievementBadge, Bool, Float, Date?)] {
        [
            // Fully earned badges
            (allBadges[0], true, 1.0, Date().addingTimeInterval(-86400 * 30)), // Earned 30 days ago
            (allBadges[6], true, 1.0, Date().addingTimeInterval(-86400 * 5)),  // Earned 5 days ago
            (allBadges[9], true, 1.0, Date().addingTimeInterval(-86400 * 15)), // Earned 15 days ago
            (allBadges[17], true, 1.0, Date().addingTimeInterval(-86400 * 2)), // Earned 2 days ago

            // Partially completed badges
            (allBadges[1], false, 0.6, nil),  // 60% complete
            (allBadges[7], false, 0.3, nil),  // 30% complete
            (allBadges[10], false, 0.5, nil), // 50% complete
            (allBadges[12], false, 0.7, nil), // 70% complete
            (allBadges[15], false, 0.8, nil), // 80% complete

            // Not started badges
            (allBadges[2], false, 0.0, nil),
            (allBadges[11], false, 0.0, nil),
            (allBadges[16], false, 0.0, nil),
            (allBadges[19], false, 0.0, nil),
            (allBadges[20], false, 0.0, nil)
        ]
    }
}