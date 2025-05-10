# VisitedStates App - Comprehensive Testing Guide

*Test plans, procedures, and automation strategies for ensuring app quality*

## Table of Contents
- [Introduction](#introduction)
- [Test Environments](#test-environments)
- [Smoke Testing Suite](#smoke-testing-suite)
- [Comprehensive Test Cases](#comprehensive-test-cases)
- [Automated Testing](#automated-testing)
- [Performance Testing](#performance-testing)
- [Regression Testing](#regression-testing)
- [Testing Checklist](#testing-checklist)

## Introduction

This guide provides a comprehensive testing strategy for the VisitedStates app. It includes smoke tests for rapid validation, detailed test cases for thorough testing, and automation strategies to ensure consistent quality.

### Testing Principles

1. **Coverage First**: Test all critical paths and user scenarios
2. **Automation Where Possible**: Automate repeatable tests
3. **Edge Case Focus**: Pay special attention to boundary conditions
4. **Real-World Simulation**: Test under realistic conditions
5. **Regression Prevention**: Ensure fixes don't break existing functionality

### Test Types

- **Functional Testing**: Verifies feature functionality
- **UI Testing**: Validates interface appearance and behavior
- **Integration Testing**: Tests component interactions
- **Performance Testing**: Measures efficiency and resource usage
- **Compatibility Testing**: Validates behavior across devices and iOS versions

## Test Environments

### Physical Devices (Primary)

The following physical devices should be used for complete test passes:
- iPhone with iOS 17.5+ (Primary test device)
- iPhone with older iOS version (Compatibility testing)
- iPad with iOS 17.5+ (Secondary testing - although app is iPhone-only, ensure it runs acceptably)

### Simulators (Supplementary)

- Multiple iPhone simulators with various screen sizes
- iOS 17.5+ simulator (Latest)
- iOS 16.0 simulator (Compatibility)

### Test Data Requirements

1. **GPX Files**:
   - State Boundary Test: Routes that cross state boundaries
   - "Four Corners" Test: Routes near the Four Corners (UT/CO/NM/AZ)
   - Border Edge Case: Routes along complex state boundaries
   - Multi-State Travel: Routes through multiple states in sequence
   - **Included file**: Ohio_WV_PA_Test.gpx

2. **CloudKit Test Data**:
   - Clean database setup for fresh install testing
   - Pre-populated database for sync testing
   - Conflict test data for resolution testing

3. **Network Conditions**:
   - Test with WiFi
   - Test with cellular data
   - Test with poor connectivity
   - Test with airplane mode

## Smoke Testing Suite

The smoke test suite verifies essential functionality in under 15 minutes. Run this after every significant code change or before beginning a testing cycle.

### ST-1: App Launch and Initial Setup

| ID | Test Case | Expected Result | Priority |
|---|---|---|---|
| ST-1.1 | Fresh install & first launch | App launches, intro animation plays, permission prompts appear | Critical |
| ST-1.2 | Grant location permissions | Location permission dialog displays, app accepts permission | Critical |
| ST-1.3 | Basic map rendering | US map displays with state boundaries | Critical |

### ST-2: Core State Detection

| ID | Test Case | Expected Result | Priority |
|---|---|---|---|
| ST-2.1 | Simulate location in a state | State correctly detected and highlighted | Critical |
| ST-2.2 | Notification for new state | Notification appears with state name | Critical |
| ST-2.3 | State added to visited list | State appears in visited states list | Critical |

### ST-3: Basic Settings

| ID | Test Case | Expected Result | Priority |
|---|---|---|---|
| ST-3.1 | Open settings | Settings screen displays correctly | High |
| ST-3.2 | Change map colors | Map updates with new colors | High |
| ST-3.3 | Toggle notifications | Notification setting changes | High |

### ST-4: State Editing

| ID | Test Case | Expected Result | Priority |
|---|---|---|---|
| ST-4.1 | Open edit view | State list displays with toggles | High |
| ST-4.2 | Add state manually | State added and reflected on map | High |
| ST-4.3 | Remove state | State removed and reflected on map | High |

### ST-5: Basic Sharing

| ID | Test Case | Expected Result | Priority |
|---|---|---|---|
| ST-5.1 | Generate share image | Share screen appears with map | Medium |
| ST-5.2 | Share sheet displays | System share options appear | Medium |

## Comprehensive Test Cases

### 1. Location Services and State Detection

#### TC-1.1: Location Permissions

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-1.1.1 | Initial permission request | 1. Fresh install<br>2. Launch app | Location permission dialog displays | Critical |
| TC-1.1.2 | "When in Use" permission | 1. Select "When In Use"<br>2. Use app in foreground | Location updates received in foreground only | Critical |
| TC-1.1.3 | "Always" permission | 1. Upgrade to "Always"<br>2. Send app to background | Background location tracking works | Critical |
| TC-1.1.4 | Permission denied | 1. Deny location permission<br>2. Observe behavior | App functions with manual mode, shows permission prompt | Critical |
| TC-1.1.5 | Permission prompt after denial | 1. Deny permission<br>2. Tap "Allow Location" in app | Deep links to settings or shows clear instructions | High |

#### TC-1.2: Basic State Detection

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-1.2.1 | Enter new state | 1. Set location in State A<br>2. Observe detection | State A correctly detected and highlighted | Critical |
| TC-1.2.2 | Move within same state | 1. Move location within State A<br>2. Observe behavior | No change in detected state | Critical |
| TC-1.2.3 | Cross state boundary | 1. Move from State A to State B<br>2. Observe detection | State B correctly detected, both states highlighted | Critical |
| TC-1.2.4 | Re-enter previously visited state | 1. Visit State A, then B<br>2. Return to State A | State A remains in visited list, no duplicate | High |

#### TC-1.3: Fallback Detection Methods

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-1.3.1 | Border region detection | 1. Set location near state border<br>2. Observe detection | Correct state detected using expanded grid search | High |
| TC-1.3.2 | Recent nearby detection | 1. Set location where direct detection fails<br>2. Near recently detected state | Correct state detected using recent nearby algorithm | Medium |
| TC-1.3.3 | Large distance jump | 1. Set location in State A<br>2. Jump >100km to State B | Correctly identifies as airport arrival scenario | Medium |

#### TC-1.4: Location Filtering

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-1.4.1 | Speed threshold | 1. Set location with speed > 100mph<br>2. Observe filtering | Location update filtered out | High |
| TC-1.4.2 | Altitude threshold | 1. Set location with altitude > 10,000ft<br>2. Observe filtering | Location update filtered out | High |
| TC-1.4.3 | Accuracy threshold | 1. Set location with horizontal accuracy > 1000m<br>2. Observe filtering | Location update filtered out | High |
| TC-1.4.4 | Valid location | 1. Set location with valid parameters<br>2. Observe processing | Location update processed normally | Critical |

### 2. Notification System

#### TC-2.1: Basic Notifications

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-2.1.1 | New state notification | 1. Enter new state<br>2. Observe notification | Notification appears with state name | Critical |
| TC-2.1.2 | Notification content | 1. Receive state notification<br>2. Check notification content | Title: "Welcome to [State]!"<br>Body: State factoid | High |
| TC-2.1.3 | Notification action | 1. Receive notification<br>2. Tap notification | App opens to map view | High |

#### TC-2.2: Notification Settings

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-2.2.1 | Disable notifications | 1. Disable notifications in settings<br>2. Enter new state | No notification sent | High |
| TC-2.2.2 | New states only | 1. Enable "Notify Only for New States"<br>2. Enter already visited state | No notification sent | High |
| TC-2.2.3 | All state changes | 1. Disable "Notify Only for New States"<br>2. Enter already visited state | Notification sent | High |

#### TC-2.3: Factoid System

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-2.3.1 | State-specific factoid | 1. Enter state with CloudKit factoids<br>2. Check notification | State-specific factoid displayed | Medium |
| TC-2.3.2 | Generic factoid fallback | 1. Enter state without specific factoids<br>2. With no network | Generic factoid displayed | Medium |
| TC-2.3.3 | Factoid caching | 1. Load factoids with network<br>2. Enter airplane mode<br>3. Enter new state | Cached factoids used | Medium |

#### TC-2.4: Edge Cases

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-2.4.1 | Duplicate notification prevention | 1. Receive notification in background<br>2. Open app | No duplicate notification | Critical |
| TC-2.4.2 | Background delivery | 1. Send app to background<br>2. Simulate new state entry | Notification delivered in background | High |
| TC-2.4.3 | Network unavailable | 1. Enter airplane mode<br>2. Enter new state | Notification with fallback factoid | Medium |

### 3. User Interface

#### TC-3.1: Main Map View

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-3.1.1 | Map initial render | 1. Launch app<br>2. Observe main view | US map displays with correct boundaries | Critical |
| TC-3.1.2 | Visited states highlighting | 1. Visit/add multiple states<br>2. Observe map | Visited states highlighted with fill color | Critical |
| TC-3.1.3 | State count | 1. Visit/add multiple states<br>2. Check state counter | Counter shows correct "X/50 States Visited" | High |
| TC-3.1.4 | Control buttons | 1. Launch app<br>2. Check UI buttons | Share, Edit, Settings buttons visible and functional | High |

#### TC-3.2: Alaska and Hawaii Handling

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-3.2.1 | Inset display | 1. Visit continental states + AK/HI<br>2. Observe map | Alaska and Hawaii display as insets | High |
| TC-3.2.2 | Only Alaska visited | 1. Visit only Alaska<br>2. Observe map | Full-screen Alaska display | Medium |
| TC-3.2.3 | Only Hawaii visited | 1. Visit only Hawaii<br>2. Observe map | Full-screen Hawaii display | Medium |
| TC-3.2.4 | Only AK and HI visited | 1. Visit only Alaska and Hawaii<br>2. Observe map | Split-screen display with both states | Medium |

#### TC-3.3: Settings View

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-3.3.1 | Settings load | 1. Tap settings button<br>2. Observe view | All settings categories display correctly | High |
| TC-3.3.2 | Notification toggles | 1. Open settings<br>2. Toggle notification settings | Toggles update and persist | High |
| TC-3.3.3 | Color pickers | 1. Open settings<br>2. Change map colors | Color pickers work, changes apply to map | High |
| TC-3.3.4 | Reset to defaults | 1. Change settings<br>2. Tap reset button | Settings return to default values | Medium |

#### TC-3.4: Edit States View

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-3.4.1 | State list display | 1. Tap edit button<br>2. Observe view | Alphabetical list of all 50 states + DC | High |
| TC-3.4.2 | GPS-verified states | 1. Visit state via GPS<br>2. Open edit view | GPS-visited states shown in bold | Medium |
| TC-3.4.3 | Add state manually | 1. Open edit view<br>2. Toggle unvisited state | State added to visited list and map | High |
| TC-3.4.4 | Remove state | 1. Open edit view<br>2. Toggle visited state | State removed from visited list and map | High |

#### TC-3.5: Share Functionality

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-3.5.1 | Generate image | 1. Tap share button<br>2. Observe preview | Share preview generates with correct content | High |
| TC-3.5.2 | Image quality | 1. Generate share image<br>2. Check image details | Image is high quality with correct colors | Medium |
| TC-3.5.3 | Sharing text | 1. Generate share<br>2. Check share sheet | Share includes appropriate text with state count | Medium |
| TC-3.5.4 | Share completion | 1. Complete share flow<br>2. Return to app | App returns to normal state after sharing | Medium |

### 4. Cloud Synchronization

#### TC-4.1: Basic Sync

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-4.1.1 | Initial sync | 1. Fresh install with iCloud account<br>2. Launch app | App fetches any existing data from iCloud | Critical |
| TC-4.1.2 | Background sync | 1. Make changes to states<br>2. Send app to background | Changes synced to iCloud | Critical |
| TC-4.1.3 | Foreground fetch | 1. Make changes on Device A<br>2. Open app on Device B | Device B fetches and displays changes | Critical |

#### TC-4.2: Conflict Resolution

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-4.2.1 | State conflicts | 1. Edit states on Device A offline<br>2. Edit differently on Device B offline<br>3. Connect both to network | Conflicts resolved correctly, no data loss | High |
| TC-4.2.2 | Settings conflicts | 1. Change settings on Device A offline<br>2. Change on Device B offline<br>3. Connect both to network | Settings merged with newer timestamps winning | High |
| TC-4.2.3 | Badge conflicts | 1. Earn badge on Device A offline<br>2. Not earned on Device B<br>3. Sync both | Badge preserved as earned on both devices | Medium |

#### TC-4.3: Edge Cases

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-4.3.1 | No iCloud account | 1. Launch with no iCloud account<br>2. Use app | App functions locally without sync | High |
| TC-4.3.2 | Network interruption | 1. Start sync<br>2. Disconnect network<br>3. Reconnect | Sync resumes or restarts properly | High |
| TC-4.3.3 | Multiple devices | 1. Use app on 3+ devices<br>2. Make different changes on each<br>3. Sync | All devices converge to consistent state | Medium |
| TC-4.3.4 | iCloud account change | 1. Use with Account A<br>2. Switch to Account B<br>3. Observe behavior | App handles account change gracefully | Medium |

### 5. Edge Cases and Error Handling

#### TC-5.1: App Lifecycle

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-5.1.1 | Low memory warning | 1. Run memory-intensive apps<br>2. Switch to VisitedStates | App handles low memory gracefully | High |
| TC-5.1.2 | Background time limit | 1. Send to background<br>2. Wait for background time limit | Background tasks complete or save state | High |
| TC-5.1.3 | Force quit recovery | 1. Make changes<br>2. Force quit app<br>3. Restart | Changes preserved, app recovers gracefully | High |
| TC-5.1.4 | iOS update | 1. Update iOS version<br>2. Launch app | App functions correctly after OS update | Medium |

#### TC-5.2: Location Edge Cases

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-5.2.1 | GPS signal loss | 1. Start location tracking<br>2. Enter area with no GPS signal | App handles signal loss gracefully | High |
| TC-5.2.2 | Location permission revoked | 1. Grant location permission<br>2. Revoke in settings<br>3. Return to app | App detects permission change and adapts | High |
| TC-5.2.3 | Very rapid state changes | 1. Simulate crossing multiple state borders quickly<br>2. Observe behavior | All states correctly recorded, no missed states | Medium |
| TC-5.2.4 | Location at exact border | 1. Set location exactly on state border<br>2. Observe detection | Consistently picks one state via fallback methods | Medium |

#### TC-5.3: Data Scenarios

| ID | Test Case | Steps | Expected Result | Priority |
|---|---|---|---|---|
| TC-5.3.1 | All states visited | 1. Mark all 50 states as visited<br>2. Observe map and counter | Map shows all states visited, counter shows "50/50" | Medium |
| TC-5.3.2 | No states visited | 1. Fresh install<br>2. Observe map | Map shows no states visited, counter shows "0/50" | Medium |
| TC-5.3.3 | Data corruption | 1. Corrupt local data (if possible)<br>2. Launch app | App recovers or resets data gracefully | High |
| TC-5.3.4 | Limited storage | 1. Fill device storage<br>2. Try to use app | App handles limited storage gracefully | Medium |

## Automated Testing

### XCTest Framework Setup

The VisitedStates app should implement automated tests using XCTest framework with the following components:

#### 1. Unit Tests

Create unit tests for core business logic:

```swift
import XCTest
@testable import VisitedStates

class StateDetectionTests: XCTestCase {
    
    var detectionService: StateDetectionService!
    var mockBoundaryService: MockBoundaryService!
    var mockSettings: MockSettingsService!
    
    override func setUp() {
        super.setUp()
        mockBoundaryService = MockBoundaryService()
        mockSettings = MockSettingsService()
        detectionService = StateDetectionService(
            locationService: MockLocationService(),
            boundaryService: mockBoundaryService,
            settings: mockSettings,
            cloudSync: MockCloudSyncService(),
            notificationService: MockNotificationService()
        )
    }
    
    func testStateDetection() {
        // Test direct detection
        let nyCoordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        mockBoundaryService.mockStateName = "New York"
        
        let result = detectionService.detectStateWithFallbacks(
            for: CLLocation(latitude: nyCoordinate.latitude, longitude: nyCoordinate.longitude)
        )
        
        XCTAssertEqual(result, "New York", "Should detect New York correctly")
    }
    
    // Additional tests for fallback methods, filtering, etc.
}
```

#### 2. UI Tests

Implement UI tests for critical user flows:

```swift
import XCTest

class VisitedStatesUITests: XCTestCase {
    
    let app = XCUIApplication()
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchArguments = ["UI-TESTING"]
        app.launch()
    }
    
    func testBasicNavigation() {
        // Test opening settings
        app.buttons["settingsButton"].tap()
        XCTAssert(app.navigationBars["Settings"].exists, "Settings screen should appear")
        
        // Close settings
        app.buttons["Done"].tap()
        
        // Test opening edit view
        app.buttons["editButton"].tap()
        XCTAssert(app.navigationBars["Edit States"].exists, "Edit States screen should appear")
    }
    
    // Additional UI tests for state toggling, color changes, etc.
}
```

#### 3. Performance Tests

Implement performance tests for critical operations:

```swift
func testStateDetectionPerformance() {
    let location = CLLocation(latitude: 40.7128, longitude: -74.0060)
    
    measure {
        // This will be measured for performance
        for _ in 0..<100 {
            _ = detectionService.detectStateWithFallbacks(for: location)
        }
    }
}
```

### Test Data Mocks

Create mock services and data for testing:

```swift
class MockBoundaryService: StateBoundaryServiceProtocol {
    var mockStateName: String?
    
    func stateName(for coordinate: CLLocationCoordinate2D) -> String? {
        return mockStateName
    }
    
    func loadBoundaryData() {
        // No-op for testing
    }
}

class MockLocationService: LocationServiceProtocol {
    var currentLocation = CurrentValueSubject<CLLocation?, Never>(nil)
    
    func startLocationUpdates() {
        // No-op for testing
    }
    
    func stopLocationUpdates() {
        // No-op for testing
    }
}
```

### Automated Test Coverage Goals

Aim for the following test coverage:

1. **Core Logic**: 80%+ code coverage
   - State detection algorithms
   - CloudKit synchronization logic
   - Data model operations

2. **UI Flows**: Cover all critical paths
   - App launch flow
   - State toggling
   - Settings changes
   - Sharing flow

3. **Performance Baseline**:
   - State detection: <10ms per operation
   - Map rendering: <100ms for full render
   - Cloud sync: <2s for standard operation

### Continuous Integration Setup

Automate testing with GitHub Actions or similar:

```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v2
    - name: Set up Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '14.x'
    - name: Build and Test
      run: |
        xcodebuild test -scheme VisitedStates -destination 'platform=iOS Simulator,name=iPhone 14,OS=16.0'
```

## Performance Testing

### Key Performance Indicators

#### 1. Location Processing

| Metric | Target | Test Method |
|---|---|---|
| State detection time | <15ms | Measure time from location update to state determination |
| Background location battery usage | <2% per hour | Monitor battery usage during extended background tracking |
| Location filter efficiency | >98% accuracy | Analyze filtered vs. accepted locations for correctness |

#### 2. UI Responsiveness

| Metric | Target | Test Method |
|---|---|---|
| App launch time | <2 seconds | Measure time from tap to interactive UI |
| Map render time | <100ms | Measure time to render full US map with visited states |
| Settings change application | <50ms | Measure time from toggle to UI update |
| Share image generation | <500ms | Measure time to create shareable image |

#### 3. Data Operations

| Metric | Target | Test Method |
|---|---|---|
| CloudKit sync time | <3 seconds | Measure time for complete sync cycle |
| Local data read time | <20ms | Measure time to load all visited states |
| Local data write time | <30ms | Measure time to save state changes |

### Performance Test Procedures

#### Battery Life Testing

1. **Background Location Tracking**:
   - Start app with fully charged device
   - Allow to run in background for 4 hours
   - Measure battery drain percentage
   - Target: <8% battery usage for 4 hours of background tracking

2. **Continuous Usage**:
   - Use app actively for 30 minutes (simulating travel)
   - Measure battery drain percentage
   - Target: <5% battery usage for 30 minutes of active use

#### Memory Usage Testing

1. **Extended Operation**:
   - Run app for 8+ hours in background mode
   - Check for memory leaks using Instruments
   - Target: No significant memory growth over time

2. **Peak Memory Usage**:
   - Measure memory usage during high-activity periods
   - Test with all 50 states visited for maximum data load
   - Target: <100MB memory usage in worst case

#### Storage Testing

1. **Data Size**:
   - Measure storage requirements with all states visited
   - Include factoid cache and settings
   - Target: <5MB total storage

## Regression Testing

### Automated Regression Suite

Implement a dedicated regression test suite that covers:

1. **Fixed Bug Verification**: Tests for all previously fixed bugs
2. **Core Functionality**: Tests that verify critical app behavior
3. **Edge Cases**: Tests for boundary conditions and rare scenarios

### Regression Test Triggers

Run the regression suite automatically on:
- Every pull request merge to main branch
- Before each release build
- After major iOS updates
- When changing core functionality

### Regression Test Checklist

- [ ] All unit tests pass
- [ ] All UI tests pass
- [ ] Performance tests meet or exceed baseline
- [ ] Manual verification of top 5 critical user flows
- [ ] Manual verification of all previously fixed bugs

## Testing Checklist

### Pre-Release Testing Checklist

**Basic Functionality:**
- [ ] App launches successfully
- [ ] Location permissions work properly
- [ ] State detection is accurate
- [ ] Map displays correctly
- [ ] Settings can be changed and persist
- [ ] States can be manually edited
- [ ] Sharing functionality works

**Advanced Functionality:**
- [ ] CloudKit sync works across devices
- [ ] Background location tracking works
- [ ] Notifications are delivered correctly
- [ ] State factoids appear in notifications
- [ ] Alaska and Hawaii display correctly in all scenarios

**Error Handling:**
- [ ] App handles no network gracefully
- [ ] App handles permission changes gracefully
- [ ] App recovers from background termination
- [ ] App handles storage limitations

**Performance:**
- [ ] App meets all performance targets
- [ ] Battery usage is within acceptable limits
- [ ] Memory usage is stable over time

### Version-Specific Test Plan

For version 1.0.9, focus testing on:
1. Duplicate notification fix (priority: critical)
2. Factoid system improvements (priority: high)
3. Thread safety improvements (priority: high)
4. Dark and Tinted Mode App Icons (priority: medium)

| Issue | Test Cases | Expected Result |
|---|---|---|
| Duplicate notifications | TC-2.4.1, TC-2.4.2 | No duplicate notifications when opening app after background notification |
| Factoid system | TC-2.3.1, TC-2.3.2, TC-2.3.3 | Factoids load correctly, cache works, default factoids display |
| Thread safety | Run under Thread Sanitizer | No thread safety warnings |
| App icons | Check system settings | Dark and tinted icons available in system settings |