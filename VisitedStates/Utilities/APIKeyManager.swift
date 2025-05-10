import Foundation

/// Helper functions for securely managing API keys and other sensitive information
/// Add this to your .gitignore to prevent it from being committed: VisitedStates/Utilities/APIKeys.swift

/// Main function for getting API keys from a secure location
func getAPIKey() -> String {
    #if DEBUG
    // In debug mode, try to get key from local file (not committed to git)
    return getLocalAPIKey()
    #else
    // In production, get key from secure storage
    return getProductionAPIKey()
    #endif
}

/// Get API key for debug environments - reads from a local file not committed to Git
private func getLocalAPIKey() -> String {
    // Try to get key from APIKeys file (should be added to .gitignore)
    if let key = apiKeyFromLocalFile() {
        return key
    }
    
    // Fall back to a built-in key if no local file is found
    // This is just for development convenience
    // IMPORTANT: You should NEVER use this key in production
    return "REPLACE_WITH_DEVELOPMENT_KEY_ONLY"
}

/// Get API key for production environments - reads from a secure location
private func getProductionAPIKey() -> String {
    // In a real app, this would read from KeyChain or from the server
    // For now, we're reading from Info.plist (which is still not ideal but better than hardcoding)
    if let key = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_SHEETS_API_KEY") as? String {
        return key
    }
    
    // If no key is found (which shouldn't happen in production), return an empty string
    // The app will fail to fetch factoids, but at least the key isn't exposed
    return ""
}

/// Reads the API key from a local file that's not committed to Git
private func apiKeyFromLocalFile() -> String? {
    // Try to read from APIKeys.swift (which should be in .gitignore)
    guard let keyFilePath = Bundle.main.path(forResource: "APIKeys", ofType: "plist") else {
        print("⚠️ No APIKeys.plist file found")
        return nil
    }
    
    guard let plist = NSDictionary(contentsOfFile: keyFilePath) else {
        print("⚠️ Failed to read APIKeys.plist")
        return nil
    }
    
    guard let apiKey = plist["GoogleSheetsAPIKey"] as? String else {
        print("⚠️ No GoogleSheetsAPIKey found in APIKeys.plist")
        return nil
    }
    
    return apiKey
}