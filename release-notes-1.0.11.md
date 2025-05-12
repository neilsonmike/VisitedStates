# VisitedStates v1.0.11 Release Notes

This update focuses on improving the user experience in both the onboarding process and the settings interface, with a particular emphasis on making location-related settings clearer and more informative.

## New Features

### Visual Permission Indicators
- Added an orange compass indicator on Settings button when optimal settings aren't configured
- The app now differentiates between critical settings (location permission) with a red indicator and recommended settings (background refresh, precise location) with an orange indicator

### Improved Settings Screen
- Redesigned Location Access section with clearer permission status displays
- Added informative warnings for disabled Background App Refresh and Precise Location settings
- Simplified explanatory text for permissions with more concise wording
- Made permission status indicators more consistent with black text for statuses

### Onboarding Enhancements
- Improved onboarding flow with more realistic descriptions of features
- Changed "Instant Notifications" to "State Entry Notifications" with more accurate description
- Fixed confusing UI elements that looked interactive but weren't
- Simplified explanation of background location permission requirements

### Development Mode Indicator
- Added clear "Development Build" indicators in debug builds (not visible in production)
- Visible on both main map view and About screen
- Helps testers easily identify when using a development build

## Bug Fixes
- Fixed build error related to API key access in FactoidService.swift
- Improved code organization to better handle API key security

## Technical Improvements
- Enhanced permission detection for Background App Refresh and Precise Location
- Added real-time update of permission indicators when app returns from background
- Made permission UI explanations more accurate to iOS system behaviors