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
    // MARK: - Properties
    
    // Published state that's exposed through the protocol
    var visitedStates = CurrentValueSubject<[String], Never>([])
    var stateFillColor = CurrentValueSubject<Color, Never>(.red)
    var stateStrokeColor = CurrentValueSubject<Color, Never>(.white)
    var backgroundColor = CurrentValueSubject<Color, Never>(.white)
    var notificationsEnabled = CurrentValueSubject<Bool, Never>(true)
    var speedThreshold = CurrentValueSubject<Double, Never>(44.7)
    var altitudeThreshold = CurrentValueSubject<Double, Never>(3048)
    var lastVisitedState = CurrentValueSubject<String?, Never>(nil)
    
    // Private storage for colors using the property wrapper
    @SettingsUserDefaultColor(key: "stateFillColor", defaultValue: .red)
    private var storedFillColor: Color
    
    @SettingsUserDefaultColor(key: "stateStrokeColor", defaultValue: .white)
    private var storedStrokeColor: Color
    
    @SettingsUserDefaultColor(key: "backgroundColor", defaultValue: .white)
    private var storedBackgroundColor: Color
    
    // Other user defaults storage
    @AppStorage("notificationsEnabled") private var storedNotificationsEnabled: Bool = true
    @AppStorage("speedThreshold") private var storedSpeedThreshold: Double = 44.7
    @AppStorage("altitudeThreshold") private var storedAltitudeThreshold: Double = 3048
    @AppStorage("lastVisitedState") private var storedLastVisitedState: String = ""
    @AppStorage("visitedStatesString") private var storedVisitedStatesJSON: String = ""
    
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
        speedThreshold.value = storedSpeedThreshold
        altitudeThreshold.value = storedAltitudeThreshold
        lastVisitedState.value = storedLastVisitedState.isEmpty ? nil : storedLastVisitedState
        
        // Load visited states from JSON
        loadVisitedStates()
        
        // Set up subscriptions to save changes
        setupSubscriptions()
    }
    
    // MARK: - SettingsServiceProtocol
    
    func addVisitedState(_ state: String) {
        var currentStates = visitedStates.value
        if !currentStates.contains(state) {
            currentStates.append(state)
            visitedStates.send(currentStates)
            lastVisitedState.send(state)
        }
    }
    
    func removeVisitedState(_ state: String) {
        var currentStates = visitedStates.value
        if let index = currentStates.firstIndex(of: state) {
            currentStates.remove(at: index)
            visitedStates.send(currentStates)
        }
    }
    
    func setVisitedStates(_ states: [String]) {
        visitedStates.send(states)
    }
    
    func hasVisitedState(_ state: String) -> Bool {
        return visitedStates.value.contains(state)
    }
    
    func restoreDefaults() {
        stateFillColor.send(.red)
        stateStrokeColor.send(.white)
        backgroundColor.send(.white)
        notificationsEnabled.send(true)
        speedThreshold.send(44.7)
        altitudeThreshold.send(3048)
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
                self.saveVisitedStates(states)
            }
            .store(in: &cancellables)
    }
    
    private func loadVisitedStates() {
        if let data = storedVisitedStatesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            visitedStates.send(decoded)
            print("🚩 Initial visitedStates loaded from JSON: \(decoded)")
        } else {
            visitedStates.send([])
        }
    }
    
    private func saveVisitedStates(_ states: [String]) {
        isSavingLocally = true
        
        if let data = try? JSONEncoder().encode(states),
           let json = String(data: data, encoding: .utf8) {
            storedVisitedStatesJSON = json
            print("💾 States saved to UserDefaults: \(states)")
        } else {
            print("❌ Failed to encode states to JSON")
        }
        
        isSavingLocally = false
    }
}
