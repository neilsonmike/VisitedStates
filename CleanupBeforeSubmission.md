# Files to Remove Before App Store Submission

Before submitting to the App Store, these files should be removed as they are temporary, migration-related, or testing tools not needed in the final product.

## Test Files (Safe to Remove)
- `/Users/mikeneilson/Desktop/VisitedStates/test-api-key.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/test-factoid-integration.swift`

## Migration Tools (Safe to Remove)
- `/Users/mikeneilson/Desktop/VisitedStates/FactoidMigrationApp.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/FactoidMigrationScript.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/FactoidMigrationTool.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/ImportFactoids.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/MigrateCloudKitToGoogleSheet.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/PopulateGoogleSheet.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/SimpleFactoidMigration.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/add_files_to_project.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/factoid-fetcher.swift`
- `/Users/mikeneilson/Desktop/VisitedStates/fetchreplacement.txt`

## Other Files to Check
- `/Users/mikeneilson/Desktop/VisitedStates/replace-keys.txt` (Contains the old API key - should be removed)
- `/Users/mikeneilson/Desktop/VisitedStates/NotificationService.swift.new` (Check if this is needed)

## Temporary/Backup Directories (Do Not Include in Build)
- `/Users/mikeneilson/Desktop/VisitedStates/VisitedStates_backup_v1.0.10/`
- `/Users/mikeneilson/Desktop/VisitedStates/VisitedStates_fresh/`
- `/Users/mikeneilson/Desktop/VisitedStates/VisitedStates-mirror/`
- `/Users/mikeneilson/Desktop/VisitedStates/VisitedStates-mirror.bfg-report/`

## Important Notes
1. These files don't need to be physically deleted from your development machine
2. They should simply not be included in the App Store submission
3. Most of them are already excluded from the build by not being referenced in the project file
4. Files containing API keys should be securely managed according to your security policy

## How to Check What's Included
Open the project in Xcode and review the project navigator to ensure none of the migration or test tools are included in the app target.