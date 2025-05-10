# API Key Security

This document outlines the steps taken to secure the Google Sheets API key in the VisitedStates app.

## 1. API Key Storage

- API keys are now stored in `VisitedStates/Utilities/APIKeys.plist` which is excluded from Git
- A template file `APIKeys.plist.template` is provided to show the required structure
- The `APIKeyManager` class is used to securely load keys from this file

## 2. Git Protection

### Files excluded in .gitignore:
- `VisitedStates/Utilities/APIKeys.plist`
- All files matching `**/APIKeys.plist`
- All test files containing API keys (`**/*api-key*.swift`, `**/*api_key*.swift`)
- The `TestBackup/` directory
- API key cleaning scripts

### Info.plist protection:
```bash
# Use this command to tell Git to ignore changes to Info.plist
git update-index --skip-worktree VisitedStates/Info.plist

# To start tracking changes again:
git update-index --no-skip-worktree VisitedStates/Info.plist
```

## 3. Previous Exposure Mitigation

The Git history has been cleaned and recreated to remove all instances of the exposed API key. The API key has been changed in the Google Cloud Console as well.

## 4. Security Best Practices

1. **Never commit API keys or secrets** to version control
2. Use `.gitignore` to exclude sensitive files
3. Use templates for configuration files containing secrets
4. Use `git update-index --skip-worktree` for files that might contain secrets
5. Regularly rotate API keys if there's any suspicion of exposure
6. Use environment variables for CI/CD pipelines

## 5. For New Developers

1. Copy `APIKeys.plist.template` to `APIKeys.plist`
2. Fill in your own API key obtained from the project lead
3. Run the app - keys will be loaded automatically by `APIKeyManager`