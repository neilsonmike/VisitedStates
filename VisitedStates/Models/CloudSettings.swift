import Foundation
import SwiftUI
import UIKit

/// Structure to hold user settings for cloud synchronization
public struct CloudSettings: Codable {
    // Notification settings
    var notificationsEnabled: Bool
    var notifyOnlyNewStates: Bool
    
    // Appearance settings
    var stateFillColor: EncodableColor
    var stateStrokeColor: EncodableColor
    var backgroundColor: EncodableColor
    
    // Detection settings
    var speedThreshold: Double
    var altitudeThreshold: Double
    
    // Metadata
    var lastUpdated: Date
    
    /// Creates CloudSettings from the current app settings
    public static func from(settingsService: SettingsServiceProtocol) -> CloudSettings {
        return CloudSettings(
            notificationsEnabled: settingsService.notificationsEnabled.value,
            notifyOnlyNewStates: settingsService.notifyOnlyNewStates.value,
            stateFillColor: EncodableColor(from: settingsService.stateFillColor.value),
            stateStrokeColor: EncodableColor(from: settingsService.stateStrokeColor.value),
            backgroundColor: EncodableColor(from: settingsService.backgroundColor.value),
            speedThreshold: settingsService.speedThreshold.value,
            altitudeThreshold: settingsService.altitudeThreshold.value,
            lastUpdated: Date()
        )
    }
    
    /// Apply these cloud settings to the local settings service
    public func applyTo(settingsService: SettingsServiceProtocol) {
        settingsService.notificationsEnabled.send(notificationsEnabled)
        settingsService.notifyOnlyNewStates.send(notifyOnlyNewStates)
        settingsService.stateFillColor.send(stateFillColor.toSwiftUIColor())
        settingsService.stateStrokeColor.send(stateStrokeColor.toSwiftUIColor())
        settingsService.backgroundColor.send(backgroundColor.toSwiftUIColor())
        settingsService.speedThreshold.send(speedThreshold)
        settingsService.altitudeThreshold.send(altitudeThreshold)
    }
}

/// A structure to make SwiftUI Color codable for cloud storage
public struct EncodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double
    
    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
    
    init(from color: Color) {
        // Convert SwiftUI Color to RGB components using extension
        let uiColor = UIColor(color: color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        self.opacity = Double(alpha)
    }
    
    public func toSwiftUIColor() -> Color {
        return Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}