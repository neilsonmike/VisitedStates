import Foundation

/// API key management functions as extension of Bundle
extension Bundle {
    /// Get Google Sheets API key from the appropriate secure location
    public func googleSheetsAPIKey() -> String {
        #if DEBUG
        // In debug mode, try to get key from local file (not committed to git)
        return debugGoogleSheetsAPIKey()
        #else
        // In production, get key from secure storage
        return productionGoogleSheetsAPIKey()
        #endif
    }
    
    /// Debug environment API key - reads from a local file not committed to Git
    private func debugGoogleSheetsAPIKey() -> String {
        // Try to get key from APIKeys file (should be added to .gitignore)
        if let key = apiKeyFromLocalPlist(keyName: "GoogleSheetsAPIKey") {
            return key
        }
        
        // Fall back to production key if no local file is found
        return productionGoogleSheetsAPIKey()
    }
    
    /// Production environment API key - reads from Info.plist
    private func productionGoogleSheetsAPIKey() -> String {
        // Read from Info.plist
        if let key = object(forInfoDictionaryKey: "GOOGLE_SHEETS_API_KEY") as? String, !key.isEmpty {
            return key
        }
        
        // Hardcoded fallback key - ONLY FOR DEVELOPMENT
        // In a real production app, this should never be reached
        return "AIzaSyDvIBPG13RRZs6qYL-3CQX3f3ypsNdWFDE"
    }
    
    /// Read a key from the APIKeys.plist file (which should be .gitignored)
    private func apiKeyFromLocalPlist(keyName: String) -> String? {
        guard let keyFilePath = path(forResource: "APIKeys", ofType: "plist") else {
            print("⚠️ No APIKeys.plist file found")
            return nil
        }
        
        guard let plist = NSDictionary(contentsOfFile: keyFilePath) else {
            print("⚠️ Failed to read APIKeys.plist")
            return nil
        }
        
        guard let apiKey = plist[keyName] as? String else {
            print("⚠️ No \(keyName) found in APIKeys.plist")
            return nil
        }
        
        return apiKey
    }
}

/// Global function for convenience access to the Google Sheets API key
public func getAPIKey() -> String {
    return Bundle.main.googleSheetsAPIKey()
}