# Claude Configuration and Settings

This file provides instructions and settings for Claude to use while working with this codebase.

## Build and Validation Commands

When making code changes, always run these commands to check for errors:

```bash
# Check for warnings and errors
cd /Users/mikeneilson/Desktop/VisitedStates
xcodebuild -project VisitedStates.xcodeproj -scheme VisitedStates -destination 'platform=iOS Simulator,name=iPhone 15' clean build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO | grep -i warning
```

## Important Files and Directories

- **Services/**: Contains all service classes for the app
  - **CloudSyncService.swift**: Handles syncing data with CloudKit
  - **BadgeTrackingService.swift**: Manages badges and tracking
  - **StateDetectionService.swift**: Detects when user enters states
  - **SettingsService.swift**: Handles app settings and persistence

- **Models/**: Contains data models
  - **VisitedStateModel.swift**: Core data model for app
  - **Badge.swift**: Model for achievement badges

- **Views/**: Contains all SwiftUI views

## Code Conventions

1. Log messages use emoji prefixes for clarity:
   - "🔄" for syncing operations
   - "📥" for download/fetch operations 
   - "📤" for upload operations
   - "🏆" for badge-related operations
   - "⚠️" for warnings

2. Swift naming conventions:
   - Use camelCase for variable and function names
   - Use PascalCase for type names (classes, structs, enums)

3. Error handling:
   - Use Swift's Result type for asynchronous operations
   - Log errors with appropriate emoji and clear messages
   
   
  ## Requirements Management

  - **Requirements Document**: The authoritative source for app requirements is `/Users/mikeneilson/Desktop/VisitedStates/Documentation/VisitedStatesRequirements.md`

  - **Requirements Preservation**: Before modifying any feature, review the requirements document to identify all existing functionality that must be preserved.

  - **Feature Impact Assessment**: For any code change, identify which requirements might be affected and confirm changes maintain compliance with those requirements.

  - **Requirements First Approach**:
    1. When working on a feature, first check existing requirements
    2. Alert me to any conflicts between requested changes and existing requirements
    3. Get explicit confirmation before proceeding with changes that alter required functionality

  - **Requirements Updates**: When implementing new features or changes, update the requirements document to reflect new functionality. Create a separate commit for requirements
  updates.

  - **Regression Prevention**: After implementing changes, verify compliance with ALL related requirements, not just the ones directly targeted by the change.

  - **Critical Functionality**:
    - Notification system respects user setting to not send notifications for already visited states
    - Badge earned notifications only appear once
    - Location detection works in background when permissions allow
    - CloudKit sync preserves all user data across devices
    - Map correctly displays all visited states

  - **Testing Against Requirements**: Before considering a feature complete, validate against ALL requirements that might be affected, even tangentially.   

## Testing Guidelines

1. For badge testing, use the coordinates in `badge_testing_coordinates.md`
2. Reset badges using the "Reset All Badges" button in the app's Settings (only in debug builds)

## CloudKit Structure

The app uses three CloudKit record types:
1. "EnhancedVisitedStates" - Stores detailed state visit information
2. "Badges" - Stores badge data
3. "UserSettings" - Stores user preferences

## Release Process

Before submitting to App Store, follow the checklist in `AppStoreSubmissionChecklist.md`

## Communication Preferences

  - **Feedback Style**: I prefer brutal honesty and realistic takes rather than being led on paths of maybes and "it can work." Tell me directly when something won't work or is a
   bad idea.

  - **Technical Discussions**: Focus on concrete solutions and practical approaches rather than theoretical possibilities.

  - **Problem Solving**: When multiple approaches exist, clearly rank them and explain their tradeoffs rather than presenting all options as equally viable.

  - **Code Quality**: Don't hold back criticism about code quality or design issues - I'd rather know about potential problems early.

