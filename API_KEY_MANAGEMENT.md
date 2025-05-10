# API Key Management

This document explains how API keys are handled securely in the VisitedStates app.

## API Key Storage

1. **Development Environment**:
   - API keys are stored in `VisitedStates/Utilities/APIKeys.plist`
   - This file is **excluded from Git** via the .gitignore file
   - Developers must create this file locally using the template

2. **Production Environment**:
   - API keys are stored in `VisitedStates/Info.plist` under the key `GOOGLE_SHEETS_API_KEY`
   - The production key is replaced with a placeholder `[API_KEY_PLACEHOLDER]` in the repository
   - Developers must manually add the actual key before building for production
   - Changes to Info.plist are ignored using Git's `skip-worktree` feature

## Git Configuration

To prevent accidental commits of API keys, we've configured Git to ignore changes to Info.plist:

```bash
git update-index --skip-worktree VisitedStates/Info.plist
```

To start tracking changes to Info.plist again (if needed):

```bash
git update-index --no-skip-worktree VisitedStates/Info.plist
```

## When Cloning the Repository

When you clone this repository, you'll need to:

1. Create the `VisitedStates/Utilities/APIKeys.plist` file based on the template
2. Add your actual API key to `VisitedStates/Info.plist`

## Setting Up APIKeys.plist

1. Copy `APIKeys.plist.template` to `APIKeys.plist`
2. Add your Google Sheets API key

Example content:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>GoogleSheetsAPIKey</key>
    <string>YOUR_API_KEY_HERE</string>
</dict>
</plist>
```

## Security Best Practices

1. **Never** commit API keys to the repository
2. **Always** use the secure storage mechanisms provided
3. Use restricted API keys with limitations on:
   - Which APIs they can access (Google Sheets only)
   - Which app bundle IDs can use them (neils.me.VisitedStates)
   - IP restrictions if applicable

## Runtime Key Retrieval

The app uses `getAPIKey()` function to retrieve the key at runtime:

```swift
// In debug builds, reads from APIKeys.plist
// In production, reads from Info.plist
let apiKey = getAPIKey()
```

This ensures that the correct key is used regardless of the build configuration.