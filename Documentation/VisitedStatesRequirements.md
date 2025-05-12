# VisitedStates App - Comprehensive Requirements Document

*Living documentation of the VisitedStates iOS app architecture, features, and version history*

## Table of Contents
- [User Customization Sync](#user-customization-sync)
- [State Detection System](#state-detection-system)
- [User Interface](#user-interface)
- [Notification System](#notification-system)
- [Data Models](#data-models)
- [Settings and Preferences](#settings-and-preferences)
- [App Architecture](#app-architecture)
- [Development Environment](#development-environment)
- [Testing Guide](#testing-guide)
- [Version History](#version-history)

## User Customization Sync

### 1. CloudKit Sync Data Structure

#### 1.1 Record Types and Schema
- **EnhancedVisitedStates**: Primary record for state visit data
  - `statesJSON`: String (JSON array of VisitedState objects)
  - `lastUpdated`: Date
- **Badges**: Record for user achievements
  - `badgesJSON`: String (JSON array of Badge objects)
  - `lastUpdated`: Date
- **UserSettings**: Record for user preferences
  - `settingsJSON`: String (JSON object of CloudSettings)
  - `lastUpdated`: Date
- **VisitedStates**: Legacy format for backward compatibility
  - `states`: [String] (Array of state names)
  - `lastUpdated`: Date

#### 1.2 Data Model Structure
```swift
// Core state tracking model
struct VisitedState: Codable, Equatable {
    var stateName: String
    var visited: Bool // GPS-verified
    var edited: Bool // Manually added
    var firstVisitedDate: Date?
    var lastVisitedDate: Date?
    var isActive: Bool
    var wasEverVisited: Bool
}

// Achievement tracking (implemented but not exposed to users)
struct Badge: Codable, Equatable {
    let identifier: String
    var earnedDate: Date?
    var isEarned: Bool
}

// User preferences
struct CloudSettings: Codable {
    var notificationsEnabled: Bool
    var notifyOnlyNewStates: Bool
    var stateFillColor: EncodableColor
    var stateStrokeColor: EncodableColor
    var backgroundColor: EncodableColor
    var speedThreshold: Double
    var altitudeThreshold: Double
    var lastUpdated: Date
}
```

### 2. Sync Triggers

#### 2.1 Automatic Background Sync Triggers
- When app enters background state via ScenePhase change
- When OS suspends the app (UIApplication.didEnterBackgroundNotification)
- After state detection updates the model with a newly visited state
- After manual edits to visited states in EditStatesView
- After changing any setting in SettingsView

#### 2.2 Automatic Foreground Sync Triggers
- When app enters foreground state via ScenePhase change
- When OS activates the app (UIApplication.didBecomeActiveNotification)
- On initial app launch after IntroMapView appears
- After changing any setting that affects map appearance

#### 2.3 Manual Sync Triggers
- Pull-to-refresh in ContentView (not currently implemented in UI)
- ~~Tap on sync button in settings~~ (Not implemented in UI but code infrastructure exists)
- Recovery after handling a network error

### 3. Sync Data Content

#### 3.1 States Content Example
```json
[
  {
    "stateName": "California",
    "visited": true,
    "edited": false,
    "firstVisitedDate": "2023-05-15T14:30:22Z",
    "lastVisitedDate": "2023-07-22T09:45:18Z",
    "isActive": true,
    "wasEverVisited": true
  },
  {
    "stateName": "Nevada",
    "visited": false,
    "edited": true,
    "firstVisitedDate": null,
    "lastVisitedDate": null,
    "isActive": true,
    "wasEverVisited": false
  }
]
```

#### 3.2 Badges Content Example
```json
[
  {
    "identifier": "RegionalExplorer",
    "earnedDate": "2023-06-12T18:22:45Z",
    "isEarned": true
  },
  {
    "identifier": "CoastToCoast",
    "earnedDate": null,
    "isEarned": false
  }
]
```

#### 3.3 Settings Content Example
```json
{
  "notificationsEnabled": true,
  "notifyOnlyNewStates": false,
  "stateFillColor": {
    "red": 0.8,
    "green": 0.2,
    "blue": 0.2,
    "alpha": 1.0
  },
  "stateStrokeColor": {
    "red": 1.0,
    "green": 1.0,
    "blue": 1.0,
    "alpha": 1.0
  },
  "backgroundColor": {
    "red": 0.95,
    "green": 0.95,
    "blue": 1.0,
    "alpha": 1.0
  },
  "speedThreshold": 100.0,
  "altitudeThreshold": 10000.0,
  "lastUpdated": "2023-08-15T22:14:30Z"
}
```

### 4. Conflict Resolution

#### 4.1 State Data Conflict Resolution
- Merges local and cloud data when server has newer records
- Deduplicates states by state name (dictionary keyed by state name)
- Preserves all state visits from both sources (never loses data)
- Conflict resolution priorities:
  - GPS verification: `visited = local.visited || cloud.visited`
  - Manual edits: `edited = local.edited || cloud.edited`
  - First visit date: Uses earliest date between local and cloud
  - Last visit date: Uses latest date between local and cloud
  - Active status: `isActive = local.isActive || cloud.isActive`
  - Historical verification: `wasEverVisited = local.wasEverVisited || cloud.wasEverVisited`

#### 4.2 Settings Conflict Resolution
- Uses the newer settings based on lastUpdated timestamp
- Ensures color opacity never drops below 0.1 to prevent invisible UI
- Individual settings from newer source override older ones
- Special handling for critical values (fill color must not be fully transparent)

#### 4.3 Badge Conflict Resolution
- Badges are merged with preference toward "earned" status
- Once earned, a badge is never unearned regardless of source
- Uses earliest earned date when both sources have the badge earned
- Adds any badges that exist in either source

### 5. Error Handling

#### 5.1 Network Error Handling
- Retry mechanism for network errors with exponential backoff
- Automatic retry for network unavailable (up to 3 times)
- Service unavailable handled with delayed retry (30 seconds)
- Network failure reported to user with option to retry

#### 5.2 CloudKit Error Handling
- `.serverRecordChanged`: Triggers conflict resolution
- `.unknownItem`: Creates new records for first-time sync
- `.accountRestricted`: User notified about iCloud account issues
- `.notAuthenticated`: User prompted to sign in to iCloud
- `.quotaExceeded`: User notified about iCloud storage limits

#### 5.3 Sync Status Publishing
- Real-time sync status sent via `syncStatus` CurrentValueSubject
- UI displays appropriate loading, success, or error indicators
- Detailed error reporting for debugging purposes
- Status categories: idle, syncing, success, error

### 6. Performance Optimizations

#### 6.1 Sync Queue Management
- Dedicated dispatch queue with utility QoS for all sync operations
- Prevention of concurrent syncs using atomic `isSyncing` flag
- Debounce mechanism to prevent rapid repeated syncs
- Thread safety through DispatchQueue and dispatch barriers

#### 6.2 Background Task Management
- Uses UIKit background tasks for extended processing time
- Task expiration handling with graceful termination
- State and priority preservation for background operations
- Battery optimization when battery is low

#### 6.3 Bandwidth Optimization
- Delta updates to minimize data transfer
- Differential sync for settings vs. state data
- Batch processing in background for efficiency
- Memory-efficient JSON processing

### 7. Edge Cases

#### 7.1 First-Time Sync
- Special handling when no records exist yet (creates new records)
- Default state array initialized for new users
- Default settings applied with standard color scheme
- Welcome instructions provided to new users

#### 7.2 Multiple Device Sync
- Last-writer-wins with conflict resolution
- Device clock skew handled by server timestamp verification
- Preservation of locally verified states across devices
- Badge status synchronized to always preserve achievements

#### 7.3 iCloud Account Changes
- Graceful handling of account switching
- Detection of iCloud availability changes
- Partial sync continuation after account errors
- Private database access verification

#### 7.4 Legacy Format Support
- Backward compatibility with original state array format
- Conversion between enhanced and legacy formats
- Preservation of verification status during format migrations
- Support for both iOS 15+ and older iOS versions

## State Detection System

### 1. Detection Mechanism

#### 1.1 Primary State Detection Process
- Uses GeoJSON polygon data from `us_states.geojson` for boundary definitions
- Implements point-in-polygon algorithm using MapKit's GeoJSON parsing
- Caches results to improve performance
- Updates state list when new states are detected

#### 1.2 Detection Sequence
1. Receive location update from LocationService
2. Filter invalid locations based on speed, altitude, and accuracy
3. Try direct state detection using point-in-polygon
4. If direct detection fails, try fallback methods:
   - Expanded grid search (1km, 2km, 5km radius)
   - Recent nearby detection (within 10km and last hour)
   - Airport arrival detection (100km+ jumps)
5. If state is detected, update model and trigger notification

#### 1.3 Fallback Detection Methods
```swift
// Primary detection
if let stateName = boundaryService.stateName(for: location.coordinate) {
    return stateName
}

// Expanded grid search
let distanceSteps = [0.01, 0.02, 0.05] // ~1km, 2km, 5km
for distanceDegrees in distanceSteps {
    for latOffset in [-distanceDegrees, 0, distanceDegrees] {
        for lonOffset in [-distanceDegrees, 0, distanceDegrees] {
            // Check if any nearby points are in a state
        }
    }
}

// Recent nearby detection
let maxDistance: CLLocationDistance = 10000 // 10km
let maxTimeInterval: TimeInterval = 3600 // 1 hour
// Find nearby recently detected states
```

#### 1.4 Background Task Handling
- Creates UIBackgroundTask for extended processing time
- Manages background task lifecycle with proper completion
- Ensures critical operations complete when app is in background

### 2. Location Triggers

#### 2.1 Standard Location Updates
- Foreground mode: Normal location updates (CLLocationManager.startUpdatingLocation())
- Default distance filter: 100 meters
- Desired accuracy: Best accuracy
- Updates processed by StateDetectionService immediately

#### 2.2 Background Location Updates
- Background mode: Significant location changes (CLLocationManager.startMonitoringSignificantLocationChanges())
- Triggers when device moves ~500 meters or more
- Saves battery while still detecting state changes
- Can wake app from suspended state to process locations

#### 2.3 App State Transitions
```swift
@objc private func appDidEnterBackground() {
    // Transition to background mode
    locationManager.stopUpdatingLocation()
    locationManager.startMonitoringSignificantLocationChanges()
}

@objc private func appDidBecomeActive() {
    // Transition to foreground mode
    locationManager.stopMonitoringSignificantLocationChanges()
    locationManager.startUpdatingLocation()
}
```

### 3. Location Filtering

#### 3.1 Speed Filtering
- Configurable speed threshold (default: 100mph)
- Locations above threshold rejected to avoid airplane detections
- Speed conversion from m/s to mph for user-friendly settings

#### 3.2 Altitude Filtering
- Configurable altitude threshold (default: 10000ft)
- Locations above threshold rejected to avoid airplane detections
- Altitude conversion from meters to feet for user-friendly settings

#### 3.3 Accuracy Filtering
- Horizontal accuracy threshold: 1000 meters
- Rejects very inaccurate readings
- Negative accuracy values rejected (invalid readings)

```swift
private func isValidLocation(_ location: CLLocation) -> Bool {
    // Converting values for logging and comparison
    let speedMph = location.speed * 2.23694 // m/s to mph
    let altitudeFeet = location.altitude * 3.28084 // meters to feet
    
    // Get threshold values from settings
    let speedThreshold = settings.speedThreshold.value
    let altitudeThreshold = settings.altitudeThreshold.value
    
    // Check altitude threshold
    if altitudeFeet > altitudeThreshold {
        return false
    }
    
    // Check speed threshold - only filter if speed is valid (> 0)
    if location.speed > 0 && speedMph > speedThreshold {
        return false
    }
    
    // Check horizontal accuracy - discard very inaccurate readings
    if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 1000 {
        return false
    }
    
    return true
}
```

### 4. Edge Case Handling

#### 4.1 Border Region Detection
- Expanded grid search for locations near borders
- Multiple sample points checked in a grid pattern
- Graceful degradation with increasingly wide search

#### 4.2 Airport Arrival Detection
- Detects large distance jumps (>100km)
- Special handling for flying between states
- Takes previous state and location into account

#### 4.3 Duplicate Notifications
- Detects when app returns to foreground in same state
- Suppresses duplicate notifications when:
  - App just became active AND
  - Current state matches the last notified state
- Addresses edge case of background notification followed by foreground open

#### 4.4 Location Service Recovery
- Handles location permission changes
- Recovers from location service interruptions
- Adjusts accuracy based on battery level
- Handles app being launched by location services

## User Interface

### 1. User Interface Structure

#### 1.1 Main Navigation Flow
- **ContentView**: Main screen displaying the map of visited states
- **SettingsView**: Accessed via settings button in ContentView
- **EditStatesView**: Accessed via edit button in ContentView
- **AboutView**: Accessed from SettingsView
- **IntroMapView**: Initial launch animation that appears before ContentView
- **SharePreviewView**: Used for generating shareable map images

#### 1.2 Navigation Structure
- Modal sheets are used for all secondary views (no tab bar or deep navigation hierarchy)
- Direct navigation from ContentView to SettingsView, EditStatesView
- SettingsView links to AboutView
- IntroMapView automatically transitions to ContentView after animation

### 2. Screen Functionality

#### 2.1 ContentView
- **Primary Function**: Display map of visited states with control buttons
- **Key Components**:
  - MapView as primary visual component
  - Share button to generate shareable image
  - Edit button to access state editing interface
  - Settings button to access app preferences
  - Location permission indicators
  - Telemetry overlay (hidden debug feature)

#### 2.2 MapView
- **Primary Function**: Render visited states visualization
- **Key Components**:
  - US map with state boundaries
  - Visited states highlighted with user-selected fill color
  - Special handling for Alaska and Hawaii as insets
  - State count label ("X/50 States Visited")
  - Dynamic layout based on visited states

#### 2.3 SettingsView
- **Primary Function**: Configure app preferences
- **Key Components**:
  - Notification toggles (enable/disable, notification preferences)
  - Color pickers (state fill, border, background)
  - Location permission management with instructions
  - About button to access app information
  - Reset button to restore default settings

#### 2.4 EditStatesView
- **Primary Function**: Manually edit visited states
- **Key Components**:
  - Alphabetical list of all 50 states plus DC
  - Toggle switches for visited status
  - Visual distinction for GPS-verified states (bold text)
  - Done button to save changes

#### 2.5 AboutView
- **Primary Function**: Display app information and credits
- **Key Components**:
  - App logo and version information
  - Developer information and links
  - Copyright notices
  - Credits for AI assistance

#### 2.6 OnboardingView
- **Primary Function**: Guide new users through setup process
- **Key Components**:
  - Welcome screen with app description
  - Feature explanation with more realistic descriptions
  - Permission request screens (location, notifications)
  - Guided instructions for optimal settings
  - Setup completion confirmation
  - Optional setting explanations

#### 2.7 IntroMapView
- **Primary Function**: Animated intro sequence
- **Key Components**:
  - Sequential animation of state outlines
  - App logo display
  - Cloud sync status indicators
  - Loading indicators during initialization

#### 2.8 SharePreviewView
- **Primary Function**: Generate shareable map image
- **Key Components**:
  - Formatted image with app branding
  - Map of visited states
  - State count statistics
  - Optimization for social media sharing

### 3. User Interactions

#### 3.1 Map Interaction
- Static map view without zooming or panning
- Visual representation updates automatically when states are visited
- Customizable appearance through settings

#### 3.2 State Management
- Toggle states on/off in EditStatesView
- Automatic detection via GPS location
- Clear visual distinction between GPS-verified and manually added states

#### 3.3 Settings Configuration
- Toggle notifications on/off
- Configure notification preferences for new states only
- Customize map colors through color pickers
- Access system settings for permission management

#### 3.4 Sharing Capabilities
- Generate and share map image via standard iOS share sheet
- Image includes app branding and state statistics
- Share text includes count and App Store link

### 4. Visual Design

#### 4.1 Color Scheme
- Customizable colors for key map elements:
  - Visited state fill color (default: red)
  - State border color (default: white)
  - Map background color (default: white)
- High contrast borders for better visibility

#### 4.2 Typography
- Custom font (DoHyeon-Regular) for distinctive appearance
- Bold text for GPS-verified states in edit view
- Clear hierarchy with varying text sizes

#### 4.3 Layout Adaptations
- Special layouts for different state combinations
- Adaptive layout for iPhone and iPad screen sizes
- Portrait orientation optimization

### 5. Accessibility Features

#### 5.1 Visual Accessibility
- Customizable colors to address visual preferences
- High-contrast state borders
- Clear permission status indicators with color coding

#### 5.2 Navigation Patterns
- Simple, flat navigation structure
- Standard iOS interaction patterns
- Clear button labeling with text and icons

#### 5.3 Permission Guidance
- Detailed step-by-step instructions for permissions
- Visual indicators for permission status
- Direct links to system settings where needed

## Notification System

### 1. Notification Structure

#### 1.1 Notification Content
- **Title**: "Welcome to [State Name]!"
- **Body**: State-specific factoid or generic message
- **Sound**: Default system sound
- **Category**: "STATE_ENTRY" for action handling
- **Metadata**: State name in userInfo dictionary
- **Priority**: Time-sensitive (iOS 15+) for better background delivery

#### 1.2 Notification Actions
- **View Map**: Opens app to show the visited states map
- Custom dismiss action for tracking user engagement
- State name passed through to app for context awareness

#### 1.3 Delivery Timing
- Small delay after state detection (configurable, default: 2 seconds)
- Helps ensure delivery in background mode
- Prevents rapid notification bursts when crossing multiple state lines

### 2. State Factoid System (v1.0.10+)

#### 2.1 Factoid Sources (Priority Order)
1. **Google Sheets API**: Real-time factoids from configured spreadsheet
2. **Cached Factoids**: Previously downloaded factoids from Google Sheets
3. **Simple Welcome Message**: Basic "Welcome to [state]!" as final fallback

#### 2.2 Google Sheets Structure
- **Format**: Simple spreadsheet with two columns
- **Headers**:
  - "state": String (state name)
  - "fact": String (the factoid text)
- **Access**: Public read-only via Google Sheets API v4
- **Configuration**: Sheet ID and API key stored in FactoidService

#### 2.3 Backward Compatibility (v1.0.9 and earlier)
- Single "Generic" factoid in CloudKit production environment
- Message prompts users to update to latest version
- Ensures smooth transition for users of older app versions

#### 2.3 Factoid Selection Logic
- Random selection from available factoids for variety
- Limit of 10 factoids per state query for efficiency
- Maximum of 500 total factoids cached for all states

### 3. Caching and Offline Support

#### 3.1 Cache Structure
- Dictionary mapping state names to arrays of factoid strings
- Persisted in UserDefaults as JSON
- Cache invalidation after one week (configurable)

#### 3.2 Cache Management
- **Preloading**: All state factoids fetched in background
- **Selective Updates**: New factoids appended to existing cache
- **Offline Fallbacks**: Multiple layers for connection issues
- **Memory Optimization**: Only stores text strings, not full records

#### 3.3 Cache Persistence
```swift
private func saveCachedFactoids() {
    if let encodedData = try? JSONEncoder().encode(cachedFactoids) {
        UserDefaults.standard.set(encodedData, forKey: "CachedFactoids")
    }
}

private func loadCachedFactoids() {
    if let savedData = UserDefaults.standard.data(forKey: "CachedFactoids"),
       let loadedFactoids = try? JSONDecoder().decode([String: [String]].self, from: savedData) {
        // Merge with existing factoids...
    }
}
```

### 4. User Preferences and Controls

#### 4.1 Notification Settings
- **Enable/Disable**: Master toggle for all state notifications
- **Notify Only for New States**: Only notify for first visit to a state
- Settings synchronized via CloudKit across devices

#### 4.2 Permission Management
- **Request Pattern**: One-time request when notifications first needed
- **Status Tracking**: Publisher for current authorization status
- **System Integration**: Deep links to iOS settings when needed

#### 4.3 Default Behavior
- Notifications enabled by default
- Notifies for all state changes by default (not just new states)
- Requires explicit user opt-out rather than opt-in

### 5. Edge Case Handling

#### 5.1 Duplicate Notification Prevention
- Tracks last notified state in UserDefaults
- Checks if app just became active after background notification
- Suppresses duplicate notifications for same state

#### 5.2 Connection Handling
- Multiple network check methods:
  - Reachability check for general connectivity
  - CloudKit ping for specific service availability
- Graceful degradation to cached content
- Timeout handling for slow connections (12-second limit)

#### 5.3 Background Processing
- Uses UIBackgroundTask for extended processing time
- Task tracking by state name for proper cleanup
- Queueing of pending notifications during startup
- Thread-safety checks for UI operations

#### 5.4 CloudKit Error Handling
- Specific handling for common CloudKit errors
- Exponential backoff for rate limiting
- Record-level error handling in batch operations
- Cache fallbacks for all network failures

## Data Models

### 1. Core Data Models

#### 1.1 VisitedState Model
```swift
struct VisitedState: Codable, Equatable {
    var stateName: String
    var visited: Bool // True if GPS-verified visit occurred
    var edited: Bool // True if manually added via edit
    var firstVisitedDate: Date? // First GPS visit
    var lastVisitedDate: Date? // Most recent GPS visit
    var isActive: Bool = true // Whether this state is visible in the UI
    var wasEverVisited: Bool // Historical record if this state was ever GPS verified
}
```

#### 1.2 Badge Model (Implemented but not exposed to users)
```swift
struct Badge: Codable, Equatable {
    let identifier: String
    var earnedDate: Date?
    var isEarned: Bool // Once true, never reverts to false
}

enum BadgeType: String, CaseIterable {
    case regionalExplorer = "RegionalExplorer"
    case coastToCoast = "CoastToCoast"
    case timeTraveler = "TimeTraveler"
    case quarterCentury = "QuarterCentury"
    case decathlon = "Decathlon"
}
```

#### 1.3 CloudSettings Model
```swift
struct CloudSettings: Codable {
    var notificationsEnabled: Bool
    var notifyOnlyNewStates: Bool
    var stateFillColor: EncodableColor
    var stateStrokeColor: EncodableColor
    var backgroundColor: EncodableColor
    var speedThreshold: Double
    var altitudeThreshold: Double
    var lastUpdated: Date
}
```

#### 1.4 EncodableColor Structure
```swift
struct EncodableColor: Codable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
    
    init(uiColor: UIColor) {
        // Extract components from UIColor...
    }
    
    func toUIColor() -> UIColor {
        // Convert back to UIColor...
    }
}
```

### 2. Data Storage

#### 2.1 Local Storage
- **UserDefaults**: Primary local storage mechanism
- Stores:
  - Visited states (JSON string of VisitedState array)
  - User preferences (via @AppStorage and custom property wrappers)
  - Factoid cache (Dictionary mapping state names to factoid arrays)
  - Last notified state for duplicate prevention
  - App state tracking flags

#### 2.2 CloudKit and Cloud Storage
- **CloudKit Private Database**: Stores user-specific data
- **Google Sheets API**: Stores factoid data (as of v1.0.10)
- CloudKit Record Types:
  - **EnhancedVisitedStates**: Primary state record
  - **Badges**: User achievements record
  - **UserSettings**: Preferences record
  - **VisitedStates**: Legacy format (backward compatibility)
  - **StateFactoids**: Legacy factoid storage (v1.0.9 and earlier)

#### 2.3 JSON Serialization
- All complex models serialized as JSON strings in CloudKit
- Custom coding/decoding for color values
- State arrays deduplicated during serialization
- Error handling for malformed JSON data

### 3. Data Relationships

#### 3.1 State Tracking Relationships
- One VisitedState object per US state (plus DC)
- States uniquely identified by name
- No database relationships - flat data model
- In-memory dictionaries for fast lookups

#### 3.2 Settings Relationships
- One settings object containing all preferences
- Direct mapping between UI controls and settings values
- Publisher pattern for reactive updates

#### 3.3 Badge Relationships (Implemented but not exposed to users)
- Achievements tied to specific conditions
- Badge identifiers as unique keys
- No explicit relationship to states, evaluated from state data

### 4. Data Integrity

#### 4.1 State Verification
- GPS-verified states tracked separately from manually added states
- Historical verification status (`wasEverVisited`) preserved
- First and last visit dates maintained for statistics
- Deactivation rather than deletion to preserve history

#### 4.2 Conflict Resolution
- Merging strategy combines data from multiple sources
- Preference for GPS verification over manual editing
- Earliest first visit date takes precedence
- Latest last visit date takes precedence
- True values win for boolean flags (union operation)

#### 4.3 Validation Rules
- State names must match official US state names
- Color opacity enforced minimum of 0.1 to prevent invisible UI
- Thresholds have sensible minimums and maximums
- Date values restricted to reasonable ranges

### 5. Future Extensions

#### 5.1 Badge System (Implemented but not exposed to users)
- Achievement tracking for:
  - Regional exploration (states in a region)
  - Coast-to-coast travel (both coasts visited)
  - Time-based travel (states in time period)
  - Quantity milestones (25 states - "Quarter Century")
  - Special combinations ("Decathlon")

#### 5.2 Potential Data Extensions
- Visit count tracking for multiple visits
- County-level tracking within states
- Trip grouping and labeling
- International expansion (countries, provinces)
- Custom location marking

## Settings and Preferences

### 1. Settings Categories

#### 1.1 Notification Settings
- **Enable Notifications**: Master toggle for all notifications
  - Default: Enabled
  - UserDefaults key: "notificationsEnabled"
  - Type: Bool
- **Notify Only for New States**: Limits notifications to first visits
  - Default: Disabled (notifies for all state changes)
  - UserDefaults key: "notifyOnlyNewStates"
  - Type: Bool

#### 1.2 Visual Appearance Settings
- **State Fill Color**: Color for visited states on map
  - Default: Red (.systemRed)
  - UserDefaults key: "stateFillColor"
  - Type: Custom EncodableColor (archived UIColor)
- **State Stroke Color**: Border color for all states
  - Default: White (.white)
  - UserDefaults key: "stateStrokeColor"
  - Type: Custom EncodableColor (archived UIColor)
- **Background Color**: Map background color
  - Default: White (.white)
  - UserDefaults key: "backgroundColor"
  - Type: Custom EncodableColor (archived UIColor)

#### 1.3 Location Settings
- **Speed Threshold**: Maximum speed (mph) for valid state detection
  - Default: 100.0 mph
  - UserDefaults key: "speedThreshold"
  - Type: Double
  - Note: UI shows 44.7 but internally hardcoded to 100.0
- **Altitude Threshold**: Maximum altitude (feet) for valid state detection
  - Default: 10000.0 feet
  - UserDefaults key: "altitudeThreshold"
  - Type: Double
  - Note: UI shows 3048 but internally hardcoded to 10000.0

### 2. Settings Storage

#### 2.1 Local Storage
- SwiftUI @AppStorage for simple types
- Custom @SettingsUserDefaultColor wrapper for color values
- UserDefaults for persistence across app launches
- Combine publishers for reactive updates

#### 2.2 CloudKit Storage
- All settings synchronized via CloudKit
- Encoded as JSON in UserSettings record
- Conflict resolution based on lastUpdated timestamp
- Automatic sync on app background/foreground

#### 2.3 Implementation
```swift
// SwiftUI property wrappers for simple settings
@AppStorage("notificationsEnabled") var notificationsEnabled = true
@AppStorage("notifyOnlyNewStates") var notifyOnlyNewStates = false

// Custom property wrapper for color storage
@SettingsUserDefaultColor(key: "stateFillColor", defaultValue: .systemRed)
var stateFillColor: UIColor

// Combine publishers for reactive components
let speedThreshold = CurrentValueSubject<Double, Never>(100.0)
let altitudeThreshold = CurrentValueSubject<Double, Never>(10000.0)
```

### 3. Settings UI

#### 3.1 Settings View Organization
- Organized into logical sections:
  - Notification Controls
  - Map Appearance
  - Location Services
  - App Information
- Clear section headers and descriptions
- Toggle switches for boolean settings
- Color pickers for appearance settings

#### 3.2 Default Reset
- "Restore Defaults" button resets appearance settings
- Confirmation alert before resetting
- Gradual animation of color changes
- Resets only visual settings, not functional settings

#### 3.3 Permission Management
- Color-coded permission status indicators
- Detailed instructions for permission upgrades
- Direct link to iOS Settings via deep link
- Visual feedback about current permission level
- Warning indicators for suboptimal settings:
  - Background App Refresh status monitoring
  - Precise Location status monitoring
  - Orange warning indicators for disabled settings

#### 3.4 Visual Permission Indicators
- Red location dot on Settings button when location permission is not "Always"
- Orange compass indicator when permission is "Always" but:
  - Background App Refresh is disabled OR
  - Precise Location is disabled
- No indicator when all settings are optimal
- Indicators update when app returns from background
- Development build indicators in debug builds only

### 4. Settings Validation

#### 4.1 Color Validation
- Prevents invisible UI by enforcing minimum opacity (0.1)
- Ensures contrast between fill and stroke colors
- Preserves alpha component in color encoding/decoding
- Handles different color spaces (RGB, grayscale)

#### 4.2 Value Constraints
- Speed threshold limited to reasonable range
- Altitude threshold limited to reasonable range
- Default values applied for invalid settings
- Migration path for legacy settings formats

#### 4.3 Thread Safety
- Settings access protected for thread safety
- Flag to prevent circular updates during syncs
- Atomic operations for settings changes
- Main thread updates for UI-related settings

### 5. Settings Change Handling

#### 5.1 Change Observers
- Combine sink subscribers for reactive updates
- Automatic persistence when values change
- Delayed cloud sync after local changes
- Change notifications broadcast to interested components

#### 5.2 Impact on App Behavior
- Notification settings immediately affect notification delivery
- Appearance settings immediately update map visualization
- Location settings affect filtering of incoming locations
- All changes automatically synchronized across devices

#### 5.3 Implementation
```swift
// Initialize publishers with stored values
private func initializePublishers() {
    // Load from UserDefaults and set up sinks
    speedThreshold.sink { [weak self] newValue in
        // Handle speed threshold changes
        UserDefaults.standard.set(newValue, forKey: "speedThreshold")
    }.store(in: &cancellables)
    
    // Other settings similarly handled...
}
```

## App Architecture

### 1. Dependency Injection Pattern

#### 1.1 Core Dependencies
- **AppDependencies**: Central container for all service dependencies
  - Implements ObservableObject for SwiftUI integration
  - Provides all service instances to views
  - Uses factory methods for production and testing

#### 1.2 Services and Protocols
- **LocationService** (LocationServiceProtocol)
  - Handles location permissions and updates
  - Filters invalid locations
- **StateBoundaryService** (StateBoundaryServiceProtocol)
  - Loads and manages state boundary data
  - Provides point-in-polygon detection
- **StateDetectionService** (StateDetectionServiceProtocol)
  - Processes locations to determine states
  - Manages state entry tracking
- **NotificationService** (NotificationServiceProtocol)
  - Handles notification permissions and delivery
  - Manages factoid system
- **CloudSyncService** (CloudSyncServiceProtocol)
  - Synchronizes data with CloudKit
  - Handles conflict resolution
- **SettingsService** (SettingsServiceProtocol)
  - Manages user preferences
  - Handles state tracking and editing

#### 1.3 Implementation
```swift
class AppDependencies: ObservableObject {
    let locationService: LocationServiceProtocol
    let stateDetectionService: StateDetectionServiceProtocol
    let cloudSyncService: CloudSyncServiceProtocol
    let notificationService: NotificationServiceProtocol
    let settingsService: SettingsServiceProtocol
    let stateBoundaryService: StateBoundaryServiceProtocol
    
    static func live() -> AppDependencies {
        // Create and wire up service instances
    }
    
    static func mock() -> AppDependencies {
        // Create test instances for unit testing
    }
}
```

### 2. Reactive Data Flow

#### 2.1 Publishers and Subscribers
- Combine framework for reactive state management
- CurrentValueSubject publishers for state changes
- Subscription-based updates to minimize coupling
- Cancellable store for proper lifecycle management

#### 2.2 State Propagation
```swift
// Location updates flow
locationService.currentLocation.sink { [weak self] location in
    if let location = location {
        self?.processLocation(location)
    }
}.store(in: &cancellables)

// State detection updates flow
stateDetectionService.currentDetectedState.sink { [weak self] stateName in
    if let state = stateName, !state.isEmpty {
        self?.handleDetectedState(state)
    }
}.store(in: &cancellables)
```

### 3. App Lifecycle Management

#### 3.1 Application State Transitions
- Notification observers for app lifecycle events
- Scene phase monitoring for modern iOS apps
- Background task creation for extended processing
- Cleanup on app termination

#### 3.2 Implementation
```swift
// Register for lifecycle notifications
NotificationCenter.default.addObserver(
    self,
    selector: #selector(appDidEnterBackground),
    name: UIApplication.didEnterBackgroundNotification,
    object: nil
)

NotificationCenter.default.addObserver(
    self,
    selector: #selector(appDidBecomeActive),
    name: UIApplication.didBecomeActiveNotification,
    object: nil
)

// Handle scene phase changes
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background {
        // Background transition
    } else if newPhase == .active {
        // Foreground transition
    }
}
```

### 4. Geographic Data Management

#### 4.1 State Boundary Handling
- GeoJSON data source for state polygons
- MapKit integration for geographic calculations
- Point-in-polygon algorithm for state detection
- QuadTree implementation for efficient spatial queries

#### 4.2 Location Processing Pipeline
1. Raw location updates from CLLocationManager
2. Filtering based on speed, altitude, accuracy
3. State detection with multiple fallback algorithms
4. State model updates and notification triggers
5. CloudKit synchronization of updated state data

### 5. Threading and Performance

#### 5.1 Thread Management
- Dedicated dispatch queues for CPU-intensive operations
- Main thread validation for UI operations
- Thread-safe design for concurrent operations
- Background task extensions for critical operations

#### 5.2 Performance Optimizations
- Caching of detection results
- Spatial indexing for boundary searches
- Batch operations for CloudKit updates
- Memory-efficient JSON handling
- Delayed operations for battery conservation

## Development Environment

### 1. System Requirements

#### 1.1 Development Requirements
- Xcode 14.0 or later
- macOS 14.5 or later
- Swift 5.0 or later
- Apple Developer account for iCloud and push notifications

#### 1.2 Runtime Requirements
- iOS 17.5 or later
- iPhone devices only (no iPad-specific design)
- Internet connection for CloudKit synchronization
- iCloud account for cross-device syncing
- Location Services capability

#### 1.3 Project Configuration
- Bundle ID: me.neils.VisitedStates
- TARGETED_DEVICE_FAMILY = 1 (iPhone only)
- Portrait orientation only
- No Mac Catalyst support

### 2. Dependencies and Frameworks

#### 2.1 Built-in Frameworks
- SwiftUI (UI framework)
- CoreLocation (location services)
- MapKit (map rendering and spatial calculations)
- CloudKit (cloud synchronization)
- UserNotifications (local notifications)
- CoreData (for data model, partial implementation)

#### 2.2 Third-party Dependencies
- None - app uses only Apple frameworks

#### 2.3 Custom Fonts
- DoHyeon-Regular.ttf (included in Resources/Fonts)

### 3. Capabilities and Entitlements

#### 3.1 Required Capabilities
- iCloud with CloudKit
- Push Notifications
- Background Modes:
  - Location updates
  - Background fetch
  - Background processing
- Location when in use and always usage descriptions

#### 3.2 Entitlements
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.me.neils.VisitedStates</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
<key>com.apple.developer.usernotifications.time-sensitive</key>
<true/>
```

### 4. Map Rendering Implementation

#### 4.1 Canvas-Based Drawing
- Uses SwiftUI Canvas API for custom map rendering
- State polygons drawn directly to canvas context
- Separate views for contiguous states and Alaska/Hawaii
- Custom coordinate transformation system

#### 4.2 Coordinate System
- Uses MKMapRect for the coordinate system
- Custom transformation for geo to screen coordinates:
```swift
// Scale calculation based on a reference scale
let scaleX = size.width / paddedRect.size.width
let scaleY = size.height / paddedRect.size.height
let scale = min(scaleX, scaleY)

func transformedX(_ point: MKMapPoint) -> CGFloat {
    return CGFloat((point.x - paddedRect.origin.x) * scale + offsetX)
}

func transformedY(_ point: MKMapPoint) -> CGFloat {
    return CGFloat((point.y - paddedRect.origin.y) * scale + offsetY)
}
```

#### 4.3 Alaska and Hawaii Display
- Three display modes depending on visited states:
  1. Full screen Alaska or Hawaii (when only one is visited)
  2. Split view of Alaska and Hawaii (when only these two are visited)
  3. Inset views (when contiguous states are also visited)
- Custom map rectangles for proper viewing:
  - Alaska: lat 64.0, lon -152.0, with span 275.0 degrees
  - Hawaii: lat 20.7, lon -156.5, with span 4.0 by 30.0 degrees

#### 4.4 Layout Specifications
- Contiguous states map: 60% of view height 
- State counter: positioned at 20% of the view height
- Inset box size: 37.5% of view width
- Border line width: 0.5 points
- Padding around map: 2% of the view size

## Testing Guide

### 1. Test Environment Setup Requirements

#### 1.1 Hardware Requirements
- iPhone with GPS capabilities and iOS 17.5 or later
- Devices with various screen sizes for UI testing
- Physical devices for full location testing

#### 1.2 Software Requirements
- Xcode 14.0 or later for development and simulator testing
- iOS 17.5+ test devices
- GPX files for simulating GPS movement (e.g., Ohio_WV_PA_Test.gpx)

#### 1.3 Account Requirements
- Apple Developer account for TestFlight distribution
- iCloud account for testing cloud sync functionality

#### 1.4 Network Requirements
- Stable internet connection for cloud sync testing
- Controlled network with varied connection speeds

### 2. Manual Testing Procedures

#### 2.1 Location Services Testing
- Verify location permission request during onboarding
- Test location permission upgrade from "While Using" to "Always"
- Verify location tracking functions correctly in foreground
- Verify location tracking functions correctly in background
- Test location updates when app transitions between foreground/background

#### 2.2 State Detection Testing
- Test detection of current state based on GPS coordinates
- Verify state boundaries are correctly identified
- Test detection accuracy near state borders
- Verify states are correctly marked as visited when detected
- Test fallback detection methods for difficult locations

#### 2.3 Map Functionality Testing
- Test map rendering of visited vs. unvisited states
- Verify correct display of Alaska and Hawaii in different scenarios
- Test map UI elements for responsiveness
- Verify maps correctly display in different device orientations

#### 2.4 Settings and Preferences Testing
- Test saving and loading user preferences
- Verify color settings correctly apply to the map
- Test notification settings functionality
- Verify settings persist between app launches

#### 2.5 Sharing Functionality Testing
- Test generating a shareable image
- Verify social sharing options work correctly
- Test share sheet functionality

#### 2.6 Edit Mode Testing
- Test manual addition of states
- Test manual removal of states
- Verify edited states are correctly flagged in the system

#### 2.7 Cloud Sync Testing
- Test sync of visited states to iCloud
- Verify sync between multiple devices
- Test sync behavior with poor network conditions
- Verify sync conflict resolution

### 3. Critical User Flow Test Cases

#### 3.1 First-Time User Flow
1. Install and launch app for first time
2. Complete onboarding process
3. Grant location permissions
4. Verify initial map view is correct
5. Test initial state detection

#### 3.2 State Detection Flow
1. Simulate movement into a new state
2. Verify state detection occurs
3. Confirm notification is received
4. Check that state is marked as visited
5. Verify map is updated
6. Ensure cloud sync is triggered

#### 3.3 Sharing Flow
1. Navigate to share functionality
2. Generate shareable image
3. Verify image quality and content
4. Complete share process
5. Verify share includes correct text and image

#### 3.4 Settings Adjustment Flow
1. Navigate to settings
2. Modify notification settings
3. Adjust map colors
4. Return to main view
5. Verify settings changes are applied correctly

#### 3.5 Edit States Flow
1. Navigate to edit states view
2. Add states manually
3. Remove states
4. Verify changes reflect on map
5. Ensure cloud sync occurs

### 4. Edge Case Testing Scenarios

#### 4.1 Location Edge Cases
- Test behavior when GPS signal is lost
- Test at complex state boundaries (e.g., Four Corners)
- Test behavior with simulated rapid state changes
- Test with very high speeds (airplane/train)
- Test with high altitudes (mountains, flights)
- Test when device is in airplane mode
- Test with location services disabled

#### 4.2 App Lifecycle Edge Cases
- Test behavior when app crashes during state detection
- Test background operation limits
- Test behavior after device restart
- Test after iOS updates
- Test with low battery conditions
- Test during incoming calls/notifications

#### 4.3 Data Edge Cases
- Test with all 50 states visited
- Test with no states visited
- Test with only Alaska and Hawaii visited
- Test with corrupted local data
- Test with conflicting cloud data

#### 4.4 Device Edge Cases
- Test with low storage space
- Test with low memory conditions
- Test with battery optimization features enabled
- Test with VPN connections

### 5. Performance Testing Guidelines

#### 5.1 Resource Usage
- Measure CPU usage during active state detection
- Measure memory usage during extended operation
- Monitor battery consumption in background tracking mode
- Test performance with extended background operation

#### 5.2 Location Accuracy
- Measure state detection accuracy at various distances from borders
- Test detection latency at different movement speeds
- Compare GPS accuracy in urban vs. rural environments

#### 5.3 App Responsiveness
- Measure app launch time
- Test UI responsiveness during active tracking
- Measure time to generate share images
- Test map rendering performance with all states visited

#### 5.4 Network Performance
- Measure cloud sync speeds under various network conditions
- Test sync reliability with intermittent connectivity
- Measure data usage during normal operation

### 6. Regression Testing Guidelines

#### 6.1 When to Perform Regression Testing
- After adding new features
- After fixing bugs
- Before major version releases
- After significant iOS updates

#### 6.2 Critical Areas for Regression Testing
1. **Core Functionality**
   - State detection accuracy
   - Location permission handling
   - Background tracking capability

2. **User-Facing Features**
   - Map rendering
   - Share functionality
   - UI responsiveness

3. **Data Integrity**
   - Visited state persistence
   - Cloud sync reliability
   - Notification delivery

#### 6.3 Regression Test Procedure
1. Create a baseline test suite covering all critical functionality
2. Automate where possible using UI testing framework
3. Document manual test cases for features not suitable for automation
4. Maintain test data including GPX routes for consistent testing
5. Compare test results against baseline after each code change
6. Prioritize testing based on areas affected by changes

## Version History

### Version 1.0.11 (Current Version)
**Release Date:** November 2023
**Changes:**
- Added visual indicators for optimal permission settings
- Added orange compass indicator when Background App Refresh or Precise Location are disabled
- Redesigned Location Access section in Settings with clearer permission status displays
- Added informative warnings for disabled Background App Refresh and Precise Location
- Simplified explanatory text for permissions with more concise wording
- Improved onboarding flow with more realistic feature descriptions
- Changed "Instant Notifications" to "State Entry Notifications" with more accurate description
- Added clear "Development Build" indicators in debug builds
- Fixed build error related to API key access in FactoidService.swift
- Improved permission detection for Background App Refresh and Precise Location
- Enhanced permission UI to accurately reflect iOS system behaviors

### Version 1.0.10
**Release Date:** October 2023
**Changes:**
- Migrated factoid system from CloudKit to Google Sheets
- Added caching for factoids to improve offline functionality
- Simplified fallback logic for factoid retrieval
- Removed all factoid migration tools from the codebase
- Improved error handling for network connectivity issues
- Added smooth transition for users of older app versions
- Updated documentation to reflect completed migration
- Improved state notification system reliability

### Version 1.0.9
**Release Date:** September 2023
**Changes:**
- Fixed duplicate notifications issue when opening app after background notifications
- Improved state factoid system with better CloudKit integration
- Fixed thread safety issues with UIApplication state access
- Increased CloudKit fetch limit from 100 to 500 records
- Preserved factoid cache between app launches
- Added high-quality default factoids for all 50 states
- Improved background processing efficiency
- Added Dark and Tinted Mode App Icons
- Fixed negative speed display in debug telemetry overlay

### Version 1.0.8
**Release Date:** August 2023
**Changes:**
- Added improved location accuracy
- Enhanced state boundary detection
- Reorganized file groups in Xcode for standardization
- Various bug fixes and performance improvements
- Added telemetry debug overlay (hidden feature)