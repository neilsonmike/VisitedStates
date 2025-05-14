import Foundation
import SwiftUI
import Combine
import UIKit

/// A property wrapper to persist SwiftUI Colors using UserDefaults.
@propertyWrapper
struct SettingsUserDefaultColor {
    let key: String
    let defaultValue: Color

    var wrappedValue: Color {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
                return Color(uiColor)
            }
            return defaultValue
        }
        set {
            let uiColor = UIColor(newValue)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
    
    static func readColor(forKey key: String, defaultValue: Color) -> Color {
        if let data = UserDefaults.standard.data(forKey: key),
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
            return Color(uiColor)
        }
        return defaultValue
    }
}

class SettingsService: SettingsServiceProtocol {
    // Debug mode flag - set to false for production
    private let isDebugMode = false
    // MARK: - Properties
    
    // Published state that's exposed through the protocol
    var visitedStates = CurrentValueSubject<[String], Never>([])
    var stateFillColor = CurrentValueSubject<Color, Never>(.red)
    var stateStrokeColor = CurrentValueSubject<Color, Never>(.white)
    var backgroundColor = CurrentValueSubject<Color, Never>(.white)
    var notificationsEnabled = CurrentValueSubject<Bool, Never>(true)
    var notifyOnlyNewStates = CurrentValueSubject<Bool, Never>(false) // Default to notify for all states
    var speedThreshold = CurrentValueSubject<Double, Never>(44.7)
    var altitudeThreshold = CurrentValueSubject<Double, Never>(3048)
    var lastVisitedState = CurrentValueSubject<String?, Never>(nil)
    
    // New properties for enhanced model
    private var visitedStateModels: [VisitedState] = []
    private var badges: [Badge] = []
    
    // Private storage for colors using the property wrapper
    @SettingsUserDefaultColor(key: "stateFillColor", defaultValue: .red)
    private var storedFillColor: Color
    
    @SettingsUserDefaultColor(key: "stateStrokeColor", defaultValue: .white)
    private var storedStrokeColor: Color
    
    @SettingsUserDefaultColor(key: "backgroundColor", defaultValue: .white)
    private var storedBackgroundColor: Color
    
    // Other user defaults storage
    @AppStorage("notificationsEnabled") private var storedNotificationsEnabled: Bool = true
    @AppStorage("notifyOnlyNewStates") private var storedNotifyOnlyNewStates: Bool = false
    @AppStorage("speedThreshold") private var storedSpeedThreshold: Double = 44.7
    @AppStorage("altitudeThreshold") private var storedAltitudeThreshold: Double = 3048
    @AppStorage("lastVisitedState") private var storedLastVisitedState: String = ""
    @AppStorage("visitedStatesString") private var storedVisitedStatesString: String = ""
    
    // New storage for enhanced model
    @AppStorage("visitedStatesJSON") private var storedVisitedStatesJSON: String = ""
    @AppStorage("badgesJSON") private var storedBadgesJSON: String = ""
    
    // Private state
    private var cancellables = Set<AnyCancellable>()
    private var isSavingLocally = false
    
    // MARK: - Initialization
    
    init() {
        // Load initial values from UserDefaults
        stateFillColor.value = SettingsUserDefaultColor.readColor(forKey: "stateFillColor", defaultValue: .red)
        stateStrokeColor.value = SettingsUserDefaultColor.readColor(forKey: "stateStrokeColor", defaultValue: .white)
        backgroundColor.value = SettingsUserDefaultColor.readColor(forKey: "backgroundColor", defaultValue: .white)
        
        notificationsEnabled.value = storedNotificationsEnabled
        notifyOnlyNewStates.value = storedNotifyOnlyNewStates
        speedThreshold.value = 100.0  // Hardcoded internal value (no longer user-configurable)
        altitudeThreshold.value = 10000.0  // Hardcoded internal value (no longer user-configurable)
        lastVisitedState.value = storedLastVisitedState.isEmpty ? nil : storedLastVisitedState
        
        // Load enhanced model states
        loadVisitedStates()
        loadBadges()
        
        // Update the string array for compatibility with existing code
        updateVisitedStatesArray()
        
        // Set up subscriptions to save changes
        setupSubscriptions()
    }
    
    // MARK: - SettingsServiceProtocol
    
    func addVisitedState(_ state: String) {
        // This is a simple legacy method that adds a state via manual edit
        addStateWithDetails(state, viaGPS: false)
    }
    
    func removeVisitedState(_ state: String) {
        // In the enhanced model, we don't truly remove states, just mark them inactive
        if let index = visitedStateModels.firstIndex(where: { $0.stateName == state }) {
            var updatedState = visitedStateModels[index]
            updatedState.isActive = false
            visitedStateModels[index] = updatedState
            
            // Update the strings array for compatibility
            updateVisitedStatesArray()
            
            // Save changes
            saveVisitedStates()
        } else {
            // For backward compatibility, also check the string array
            var currentStates = visitedStates.value
            if let index = currentStates.firstIndex(of: state) {
                currentStates.remove(at: index)
                visitedStates.send(currentStates)
            }
        }
    }
    
    func setVisitedStates(_ states: [String]) {
        // Get current active states for comparison
        let currentActiveStates = visitedStateModels.filter({ $0.isActive }).map({ $0.stateName })
        
        // Find states to add (in new list but not in current active states)
        let statesToAdd = states.filter { !currentActiveStates.contains($0) }
        
        // Find states to remove (in current active states but not in new list)
        let statesToRemove = currentActiveStates.filter { !states.contains($0) }
        
        // Process additions (adding via manual edit)
        for state in statesToAdd {
            addStateWithDetails(state, viaGPS: false)
        }
        
        // Process removals (marking as inactive)
        for state in statesToRemove {
            removeVisitedState(state)
        }
        
        // Update the strings array for compatibility and save
        updateVisitedStatesArray()
        saveVisitedStates()
    }
    
    func hasVisitedState(_ state: String) -> Bool {
        // Check if state is active in the enhanced model
        if visitedStateModels.contains(where: { $0.stateName == state && $0.isActive }) {
            return true
        }
        
        // Fall back to string array for backward compatibility
        return visitedStates.value.contains(state)
    }
    
    func restoreDefaults() {
        stateFillColor.send(.red)
        stateStrokeColor.send(.white)
        backgroundColor.send(.white)
        notificationsEnabled.send(true)
        notifyOnlyNewStates.send(false) // Default to notify for all states
        speedThreshold.send(100.0)
        altitudeThreshold.send(10000.00)
        
    }
    
    // MARK: - Enhanced methods for GPS tracking
    
    /// Add a state visit detected via GPS
    func addStateViaGPS(_ state: String) {
        addStateWithDetails(state, viaGPS: true)
    }
    
    /// Check if a state was ever visited via GPS, regardless of current status
    func wasStateEverVisitedViaGPS(_ state: String) -> Bool {
        return visitedStateModels.contains(where: {
            $0.stateName == state && $0.wasEverVisited
        })
    }
    
    /// Get all states that were ever GPS verified
    func getAllGPSVerifiedStates() -> [VisitedState] {
        return visitedStateModels.filter { $0.wasEverVisited }
    }
    
    /// Get only active GPS verified states
    func getActiveGPSVerifiedStates() -> [VisitedState] {
        return visitedStateModels.filter { $0.wasEverVisited && $0.isActive }
    }
    
    /// Get all earned badges
    func getEarnedBadges() -> [Badge] {
        // First get simple badges from old storage
        let oldBadges = badges.filter { $0.isEarned }
        
        // Now get badges from the BadgeTrackingService
        let badgeTrackingService = BadgeTrackingService()
        let earnedBadgeDates = badgeTrackingService.getEarnedBadges()
        
        // Convert achievement badges to the Badge format expected by CloudKit
        var achievementBadges: [Badge] = []
        
        // For each earned badge ID and date, create a proper Badge object
        for (badgeId, earnedDate) in earnedBadgeDates {
            // Create a CloudKit-compatible Badge object
            let badge = Badge(
                identifier: badgeId,
                earnedDate: earnedDate,
                isEarned: true
            )
            achievementBadges.append(badge)
        }
        
        // Add logging to help troubleshoot
        print("🏆 Syncing \(achievementBadges.count) achievement badges and \(oldBadges.count) legacy badges to CloudKit")
        
        // Combine old and new badge systems
        var combinedBadges = oldBadges
        
        // Add achievement badges that aren't already in the combined list
        for achievementBadge in achievementBadges {
            if !combinedBadges.contains(where: { $0.identifier == achievementBadge.identifier }) {
                combinedBadges.append(achievementBadge)
            }
        }
        
        print("🏆 Total badges for CloudKit sync: \(combinedBadges.count)")
        return combinedBadges
    }
    
    // MARK: - Private methods
    
    private func setupSubscriptions() {
        // Save colors when they change
        stateFillColor
            .sink { [weak self] color in
                self?.storedFillColor = color
            }
            .store(in: &cancellables)
        
        stateStrokeColor
            .sink { [weak self] color in
                self?.storedStrokeColor = color
            }
            .store(in: &cancellables)
        
        backgroundColor
            .sink { [weak self] color in
                self?.storedBackgroundColor = color
            }
            .store(in: &cancellables)
        
        // Save other preferences when they change
        notificationsEnabled
            .sink { [weak self] enabled in
                self?.storedNotificationsEnabled = enabled
            }
            .store(in: &cancellables)
        
        notifyOnlyNewStates
            .sink { [weak self] value in
                self?.storedNotifyOnlyNewStates = value
            }
            .store(in: &cancellables)
        
        speedThreshold
            .sink { [weak self] threshold in
                self?.storedSpeedThreshold = threshold
            }
            .store(in: &cancellables)
        
        altitudeThreshold
            .sink { [weak self] threshold in
                self?.storedAltitudeThreshold = threshold
            }
            .store(in: &cancellables)
        
        lastVisitedState
            .sink { [weak self] state in
                self?.storedLastVisitedState = state ?? ""
            }
            .store(in: &cancellables)
        
        // Save visited states as JSON when they change
        visitedStates
            .sink { [weak self] states in
                guard let self = self, !self.isSavingLocally else { return }
                
                // Save to legacy format (string array)
                if let data = try? JSONEncoder().encode(states),
                   let json = String(data: data, encoding: .utf8) {
                    storedVisitedStatesString = json
                }
            }
            .store(in: &cancellables)
    }
    
    /// Add a state with detailed information about how it was added
    private func addStateWithDetails(_ state: String, viaGPS: Bool) {
        // Check if we already have this state in our data
        if let index = visitedStateModels.firstIndex(where: { $0.stateName == state }) {
            // State exists but might be inactive - update it appropriately
            var updatedState = visitedStateModels[index]
            
            if viaGPS {
                // GPS visit - update both flags and dates
                updatedState.visited = true
                updatedState.wasEverVisited = true
                
                // Update dates
                if updatedState.firstVisitedDate == nil {
                    updatedState.firstVisitedDate = Date()
                }
                updatedState.lastVisitedDate = Date()
            } else {
                // Manual edit - preserve GPS history if it exists
                if updatedState.wasEverVisited {
                    // This implements the specific use case: If a state was ever GPS-verified
                    // and is manually re-added, it retains its GPS verification status
                    updatedState.visited = updatedState.wasEverVisited
                }
                updatedState.edited = true
            }
            
            // Always make the state active again
            updatedState.isActive = true
            
            // Update the state in the array
            visitedStateModels[index] = updatedState
        } else {
            // State doesn't exist, create a new one
            let newState = VisitedState(
                stateName: state,
                visited: viaGPS,
                edited: !viaGPS,
                firstVisitedDate: viaGPS ? Date() : nil,
                lastVisitedDate: viaGPS ? Date() : nil,
                isActive: true,
                wasEverVisited: viaGPS
            )
            visitedStateModels.append(newState)
        }
        
        // Update the strings array for compatibility with existing code
        updateVisitedStatesArray()
        
        // Save changes
        saveVisitedStates()
        
        // If this was a GPS visit, check for badge awards
        if viaGPS {
            checkForBadgeAwards()
        }
    }
    
    /// Update the string array of visited states based on active states in the enhanced model
    private func updateVisitedStatesArray() {
        isSavingLocally = true
        
        // Only include active states in the string array
        let activeStates = visitedStateModels.filter { $0.isActive }.map { $0.stateName }
        visitedStates.send(activeStates)
        
        isSavingLocally = false
    }
    
    private func loadVisitedStates() {
        // First try to load the enhanced model
        if let data = storedVisitedStatesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([VisitedState].self, from: data) {
            visitedStateModels = decoded
            print("🚩 Enhanced visitedStateModels loaded: \(decoded.count) states")
        } else {
            // Fall back to the legacy string array if enhanced model isn't found
            migrateFromLegacyFormat()
        }
    }
    
    private func migrateFromLegacyFormat() {
        print("🔄 Migrating from legacy format to enhanced model")
        
        // Try to load the legacy format first
        if let data = storedVisitedStatesString.data(using: .utf8),
           let states = try? JSONDecoder().decode([String].self, from: data) {
            
            // Create enhanced models from the legacy string array
            // Since we can't tell which were GPS vs manually added in the legacy format,
            // we'll mark them all as edited for safety
            let migrationDate = Date()
            visitedStateModels = states.map { stateName in
                VisitedState(
                    stateName: stateName,
                    visited: false,
                    edited: true,
                    firstVisitedDate: migrationDate,
                    lastVisitedDate: migrationDate,
                    isActive: true,
                    wasEverVisited: false
                )
            }
            
            // Update the string array
            visitedStates.send(states)
            
            // Save in the enhanced format
            saveVisitedStates()
            
            print("🔄 Migration complete: \(states.count) states migrated")
        } else {
            // No data in either format
            visitedStateModels = []
            visitedStates.send([])
            print("🚩 No visited states data found in any format")
        }
    }
    
    private func saveVisitedStates() {
        isSavingLocally = true
        
        // Save the enhanced model
        if let data = try? JSONEncoder().encode(visitedStateModels),
           let json = String(data: data, encoding: .utf8) {
            storedVisitedStatesJSON = json
            // Only log saves during development
            if isDebugMode {
                print("💾 Enhanced model saved with \(visitedStateModels.count) states")
            }
        } else {
            print("❌ Failed to encode enhanced model")
        }
        
        isSavingLocally = false
    }
    
    private func loadBadges() {
        // Load badges from storage
        if let data = storedBadgesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Badge].self, from: data) {
            badges = decoded
            print("🏆 Loaded \(badges.count) badges")
        } else {
            // Initialize default badges if none exist
            initializeDefaultBadges()
        }
    }
    
    private func initializeDefaultBadges() {
        badges = BadgeType.allCases.map { badgeType in
            Badge(identifier: badgeType.rawValue, earnedDate: nil, isEarned: false)
        }
        saveBadges()
        print("🏆 Initialized \(badges.count) default badges")
    }
    
    private func saveBadges() {
        if let data = try? JSONEncoder().encode(badges),
           let json = String(data: data, encoding: .utf8) {
            storedBadgesJSON = json
            // Only log in debug mode
            if isDebugMode {
                print("💾 Saved \(badges.count) badges")
            }
        } else {
            print("❌ Failed to encode badges")
        }
    }
    
    private func checkForBadgeAwards() {
        // This is a placeholder for future badge award logic
        // We'll implement the actual rules when badges are fully implemented
        
        // For now, just make sure all badge types exist
        let existingBadgeTypes = badges.map { $0.identifier }
        for badgeType in BadgeType.allCases {
            if !existingBadgeTypes.contains(badgeType.rawValue) {
                badges.append(Badge(
                    identifier: badgeType.rawValue,
                    earnedDate: nil,
                    isEarned: false
                ))
            }
        }
        
        // Save any changes to badges
        saveBadges()
    }
}
