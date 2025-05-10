# Factoid Migration Guide

This document explains the migration of factoids from CloudKit to Google Sheets for the VisitedStates app, which has been completed in version 1.0.10.

## Background

The app previously stored state factoids in CloudKit, but there was an issue where factoids that existed in the development environment were not automatically migrated to the production environment. This was solved by:

1. Exporting factoids from CloudKit to a CSV file
2. Importing the CSV data into Google Sheets
3. Using Google Sheets as the factoid data source instead of CloudKit

## Migration Status: COMPLETED

As of version 1.0.10, the migration to Google Sheets has been completed. The app now exclusively uses Google Sheets for factoid retrieval, and the migration tools have been removed from the app.

## Key Changes in Version 1.0.10

1. CloudKit is no longer used for factoid retrieval
2. Google Sheets is now the exclusive source for factoids
3. Migration tools have been removed to simplify the codebase
4. Caching mechanism added for offline factoid access

## CloudKit to Google Sheets Workflow

For older versions of the app (v1.0.9 and earlier):
- A single "Generic" factoid has been added to CloudKit production environment
- This factoid will prompt users to update to the latest version
- This ensures a smooth transition for users of older versions

## Google Sheets Configuration

The app requires a properly configured Google Sheet with:
- Two columns labeled "state" and "fact"
- State names matching the 50 US states
- Factoids in the "fact" column

The Sheet ID is configured in:
- `FactoidService.swift` - Core service for Google Sheets integration
- `NotificationService+GoogleSheets.swift` - Implementation for direct API access

## Offline Support

The app now caches factoids from Google Sheets for offline use:
1. Successful factoid fetches are cached to device storage
2. When offline, the app will use cached factoids
3. If no cached factoid is available, a simple welcome message is shown

## Fallback Strategy

The order of precedence for factoid fetching is:
1. Google Sheets API (real-time)
2. Cached factoids from previous Google Sheets fetches
3. Simple welcome message ("Welcome to [state]!") if no factoid is available

## For Developers

This migration required significant changes to the app's factoid system:
1. Created a `FactoidService` for Google Sheets integration
2. Enhanced `NotificationService` with Google Sheets support
3. Added caching for offline scenarios
4. Removed CloudKit-specific factoid fetching code

## Production Deployment

When deploying this version to the App Store:

1. Ensure your Google Sheet contains factoids for all 50 states
2. Verify the Sheet is publicly accessible for reading
3. Test offline functionality by enabling Airplane Mode
4. Confirm the factoid caching works as expected

## Troubleshooting

- If factoids don't appear, check that the Google Sheets API is accessible
- Verify your API key is correctly set in `FactoidService.swift`
- Ensure your Google Sheet is publicly accessible for reading
- Check the Sheet ID is correctly configured in both service files