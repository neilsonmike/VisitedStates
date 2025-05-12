# CI Setup for VisitedStates

This document explains how to set up Continuous Integration (CI) for the VisitedStates app, particularly focusing on handling API keys.

## API Keys in CI

The app uses API keys that shouldn't be committed to the repository. Here's how we handle them in CI:

### 1. Xcode Cloud Setup

In Xcode Cloud, add the following environment variables:

- `GOOGLE_SHEETS_API_KEY`: Your Google Sheets API key
  - Go to your workflow in App Store Connect
  - Click "Edit"
  - Go to the "Environment" tab
  - Under "Environment Variables", add the variable
  - Mark it as "Secret" to keep it secure

### 2. Code Changes for CI Resilience

We've made the APIKeyManager resilient to CI environments:

1. **Environment Variable Check**:
   - APIKeyManager.swift checks for environment variables first
   - This allows Xcode Cloud to inject the API key via environment variables

2. **Info.plist Placeholder**:
   - Info.plist includes a placeholder for the API key
   - During CI builds, this gets replaced with the environment variable

3. **Fallback Mechanism**:
   - If no key is found, the app uses a dummy key for development/CI
   - This ensures the build passes even without a real key

### 3. Local Development

For local development:

- Copy `APIKeys.plist.template` to `APIKeys.plist`
- Add your actual API keys to this local file
- Make sure `.gitignore` includes `APIKeys.plist` so it's not committed

## Testing CI Setup

To test if your CI setup works:

1. Make a small change to the codebase:
   ```swift
   // Add a comment or whitespace change
   ```

2. Commit and push the change:
   ```bash
   git add .
   git commit -m "Test CI API key integration"
   git push
   ```

3. Monitor the build in Xcode Cloud
4. Verify it completes without API key errors

## Troubleshooting

If you see API key related errors:

1. **Check environment variables** in Xcode Cloud workflow
2. **Verify API key value** is correct and not empty
3. **Check build logs** for any "Using API key from..." messages
4. **Test locally** with environment variables:
   ```bash
   GOOGLE_SHEETS_API_KEY=your_key xcodebuild ...
   ```