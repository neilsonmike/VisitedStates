import Foundation

// Core data model for visited states with GPS verification tracking
struct VisitedState: Codable, Equatable {
    var stateName: String
    var visited: Bool // True if GPS-verified visit occurred
    var edited: Bool // True if manually added via edit
    var firstVisitedDate: Date? // First GPS visit (in local state timezone)
    var lastVisitedDate: Date? // Most recent GPS visit (in local state timezone)
    var isActive: Bool = true // Whether this state is visible in the UI
    var wasEverVisited: Bool // Historical record if this state was ever GPS verified
    
    // Initializer with defaults
    init(stateName: String, visited: Bool = false, edited: Bool = false,
         firstVisitedDate: Date? = nil, lastVisitedDate: Date? = nil,
         isActive: Bool = true, wasEverVisited: Bool? = nil) {
        self.stateName = stateName
        self.visited = visited
        self.edited = edited
        self.firstVisitedDate = firstVisitedDate
        self.lastVisitedDate = lastVisitedDate
        self.isActive = isActive
        // If wasEverVisited is not explicitly provided, default to current visited status
        self.wasEverVisited = wasEverVisited ?? visited
    }
}

// Badge structure for achievements
struct Badge: Codable, Equatable {
    let identifier: String
    var earnedDate: Date?
    var isEarned: Bool // Once true, never reverts to false
    var hasBeenViewed: Bool = false // Whether the badge has been viewed by the user
    
    /// Merge this badge with another one from the cloud
    /// - Parameter other: The badge to merge with
    /// - Returns: A new merged badge with the most favorable properties from both
    func mergeWith(_ other: Badge) -> Badge {
        // Determine earned date based on earned status
        var mergedEarnedDate: Date? = nil
        let isEarnedInEither = self.isEarned || other.isEarned
        
        if isEarnedInEither {
            if let selfDate = self.earnedDate, let otherDate = other.earnedDate {
                // Use the earliest date if both are available
                mergedEarnedDate = selfDate < otherDate ? selfDate : otherDate
            } else {
                // Otherwise use whichever is available
                mergedEarnedDate = self.earnedDate ?? other.earnedDate
            }
        }
        
        // Create and return the merged badge with all properties set at initialization
        return Badge(
            identifier: self.identifier,
            earnedDate: mergedEarnedDate,
            isEarned: isEarnedInEither,
            hasBeenViewed: self.hasBeenViewed || other.hasBeenViewed
        )
    }
}

// Badge types
enum BadgeType: String, CaseIterable {
    case regionalExplorer = "RegionalExplorer"
    case coastToCoast = "CoastToCoast"
    case timeTraveler = "TimeTraveler"
    case quarterCentury = "QuarterCentury"
    case decathlon = "Decathlon"
}
