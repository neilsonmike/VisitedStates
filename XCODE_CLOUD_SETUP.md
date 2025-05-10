# Xcode Cloud Setup

This document explains how to set up Xcode Cloud to work with the secure API key storage system.

## Current Status

Currently, Xcode Cloud builds are disabled because:
- API keys are stored in `APIKeys.plist` which is excluded from Git
- Xcode Cloud cannot access this file during builds
- This security measure prevents API key exposure in repositories

## Re-enabling Xcode Cloud

When you want to re-enable Xcode Cloud builds, follow these steps:

### 1. Add API Key as Environment Variable

1. Go to App Store Connect > Xcode Cloud
2. Select your workflow
3. Click "Edit Workflow"
4. Navigate to "Environment" tab
5. Add a custom environment variable:
   - Name: `GOOGLE_SHEETS_API_KEY`
   - Value: Your actual API key
6. Save changes

### 2. Create Build Script

Add a "Pre-Build Run Script" phase to your workflow that creates the APIKeys.plist file during build:

```bash
#!/bin/bash
# Create APIKeys.plist from environment variables
mkdir -p "$CI_WORKSPACE/VisitedStates/Utilities"
cat > "$CI_WORKSPACE/VisitedStates/Utilities/APIKeys.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>GoogleSheetsAPIKey</key>
    <string>$GOOGLE_SHEETS_API_KEY</string>
</dict>
</plist>
EOF

echo "Created APIKeys.plist for build"
```

### 3. Test the Build

1. Trigger a manual build to verify the script works properly
2. Check build logs to ensure no API key exposure in logs
3. If successful, enable scheduled or automatic builds

## Security Considerations

- Environment variables in Xcode Cloud are encrypted and secured
- They are not visible in build logs (unless explicitly printed)
- Consider rotating your API key periodically for additional security
- Never debug environment issues by printing the actual API key value

## Troubleshooting

If builds fail after setting up:

1. Verify environment variable is correctly named `GOOGLE_SHEETS_API_KEY`
2. Check pre-build script is executing (logs should show "Created APIKeys.plist for build")
3. Confirm the path to APIKeys.plist matches your project structure
4. Try running the build with verbose logs enabled

## Alternative Approaches

If this approach doesn't work for your setup, consider:

1. Using a different API key specifically for CI/CD
2. Implementing a development mode that doesn't require the API key
3. Using a mock service for testing during the CI pipeline