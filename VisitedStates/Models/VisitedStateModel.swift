import Foundation

//Testing
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
}

// Badge types
enum BadgeType: String, CaseIterable {
    case regionalExplorer = "RegionalExplorer"
    case coastToCoast = "CoastToCoast"
    case timeTraveler = "TimeTraveler"
    case quarterCentury = "QuarterCentury"
    case decathlon = "Decathlon"
}
