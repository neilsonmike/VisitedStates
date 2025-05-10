# VisitedStates v1.0.10 App Store Description

## App Store Release Notes
```
VisitedStates v1.0.10 enhances user experience with the following improvements:

• Improved factoid system for more reliable state information
• Enhanced security with proper API key management
• Simplified offline experience with better caching
• Fixed various minor bugs and improved overall stability
• Better handling of connectivity issues
```

## Key Changes in This Version

### 1. Factoid System Migration
- Migrated from CloudKit to Google Sheets for factoid management
- Added caching mechanism for improved offline experience
- Implemented simpler fallback chain for error handling

### 2. Security Enhancements
- Implemented proper API key management system
- Removed hardcoded API keys from source code
- Added API key restrictions (Google Sheets API only, app bundle ID restriction)
- Created template files for developer onboarding

### 3. User Experience Improvements
- Simplified notification content when factoids aren't available
- Improved handling of network connectivity issues
- Enhanced state change detection accuracy

### 4. Technical Improvements
- Cleaned up legacy migration code
- Updated documentation for future maintenance
- Set groundwork for future feature enhancements

## Additional Information for Review Team

If Apple's review team needs to test the app's factoid functionality, please ensure they enter several different states to trigger notifications with state-specific factoids. The app uses location-based triggers to detect state changes and display interesting facts about each state.

The app uses the Google Sheets API solely to retrieve educational factoids about US states. This approach allows for easier updates to factoid content without requiring app updates.

### API Usage
- Google Sheets API: Used only to fetch educational factoids about US states
- Mapbox SDK: Used for map rendering and state boundary detection
- CoreLocation: Used for user location tracking (with proper permission requests)

Thank you for reviewing VisitedStates v1.0.10!