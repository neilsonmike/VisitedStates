# Google Sheets API Integration Guide

## Overview

This document explains how the VisitedStates app integrates with Google Sheets API for factoid management, especially focusing on API key security and bundle ID verification.

## API Key Security

The Google Sheets API key is now stored in two locations:
1. `Info.plist` - For production builds
2. `APIKeys.plist` - For debug/development builds (this file is excluded from git)

### API Key Restrictions

The API key has been configured with the following restrictions:
- **API restriction**: Only works with Google Sheets API
- **iOS bundle ID restriction**: Only works with `neils.me.VisitedStates`

## Bundle ID Communication

To ensure the Google Sheets API correctly identifies our app's bundle ID, we've:
1. Created a proper `URLRequest` with custom headers
2. Added a `User-Agent` header that includes the app bundle ID
3. Added a custom `X-iOS-Bundle-Identifier` header with the bundle ID

## Factoid Fallback Chain

The app now follows a proper fallback chain for factoids:
1. First attempts to fetch live from Google Sheets API
2. If that fails, checks for locally cached factoids from previous successful fetches
3. Only if both fail, uses a generic welcome message

## Debugging Tips

- Enable more detailed logging by checking the console output
- Look for API response status codes in the console (🌐 prefix)
- Pay attention to factoid source indicators (📝 and 📦 prefixes)

## Testing

Before App Store submission:
1. Test with internet connection to verify live API fetch works
2. Test in airplane mode to verify cached factoids are used
3. Test a clean install with no internet to verify the generic fallback works

## API Key Renewal

If you need to change the API key:
1. Generate a new key in Google Cloud Console
2. Apply the same restrictions (Google Sheets API, bundle ID: neils.me.VisitedStates)
3. Update the key in both `Info.plist` and `APIKeys.plist`
4. Remember to revoke the old key after the new version is deployed

## Troubleshooting

If you encounter "API_KEY_IOS_APP_BLOCKED" errors:
- Verify the bundle ID in your Xcode project matches exactly what's in Google Cloud Console
- Check that the HTTP request is properly sending the bundle ID in headers
- Verify the key restrictions in Google Cloud Console are correctly set
- Try temporarily removing bundle ID restrictions for testing