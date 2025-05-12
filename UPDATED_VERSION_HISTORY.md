## Version History

### Version 1.0.11 (Current Version)
**Release Date:** May 2025 (Current)
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
**Release Date:** May 2025 (3 hours ago)
**Changes:**
- Catch and release program for bugs has been eliminated, back to squishing those things
- Migrated factoid system from CloudKit to Google Sheets
- Added caching for factoids to improve offline functionality
- Simplified fallback logic for factoid retrieval
- Removed all factoid migration tools from the codebase
- Improved error handling for network connectivity issues
- Added smooth transition for users of older app versions
- Updated documentation to reflect completed migration

### Version 1.0.9
**Release Date:** May 2025 (3 days ago)
**Changes:**
- Thoughtfully, methodically, artfully, and respectfully annihilated a few code goblins
- Fixed duplicate notifications issue when opening app after background notifications
- Improved state factoid system with better CloudKit integration
- Fixed thread safety issues with UIApplication state access
- Increased CloudKit fetch limit from 100 to 500 records
- Preserved factoid cache between app launches
- Improved background processing efficiency

### Version 1.0.8 
**Release Date:** May 2025 (5 days ago)
**Changes:**
- Fed all of the bugs to Moe the Leopard Gecko
- Added improved location accuracy
- Enhanced state boundary detection
- Reorganized file groups in Xcode for standardization
- Various bug fixes and performance improvements
- Added telemetry debug overlay (hidden feature)

### Version 1.0.7
**Release Date:** May 2025 (6 days ago)
**Changes:**
- Added improved onboarding flow for location and notification permissions
- Implemented cloud synchronization for app settings
- Fixed various minor bugs and performance issues

### Version 1.0.6
**Release Date:** May 2025 (1 week ago)
**Changes:**
- Added Dark Mode and Tinted Mode app icons
- Smooshed some big old hairy bugs
- Various stability improvements

### Version 1.0.5
**Release Date:** April 2025 (2 weeks ago)
**Changes:**
- Intro map animation now respects dark mode
- Removed erroneous altitude and velocity thresholds
- Fixed factoid retrieval/caching logic
- Performance optimizations

### Version 1.0.4
**Release Date:** April 2025 (2 weeks ago)
**Changes:**
- Bug fixes and stability improvements
- Performance enhancements

### Version 1.0.3
**Release Date:** April 2025 (2 weeks ago)
**Changes:**
- Moved "Edit States" button directly to Map View for easier editing
- Switched share sheet image to a custom image
- Improved user experience
- Bug fixes

### Version 1.0.2
**Release Date:** April 2025 (2 weeks ago)
**Changes:**
- Initial public release
- Core functionality implemented