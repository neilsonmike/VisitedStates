import Foundation

/// API key management functions as extension of Bundle
extension Bundle {
    /// Get Google Sheets API key from the appropriate secure location
    public func googleSheetsAPIKey() -> String {
        // First check for environment variable (for CI environments)
        if let envKey = ProcessInfo.processInfo.environment["GOOGLE_SHEETS_API_KEY"], !envKey.isEmpty {
            print("📱 Using API key from environment variable")
            return envKey
        }

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

        print("📱 No local API key found, using fallback")

        // Fall back to production key if no local file is found
        return productionGoogleSheetsAPIKey()
    }

    /// Production environment API key - reads from Info.plist
    private func productionGoogleSheetsAPIKey() -> String {
        // Read from Info.plist
        if let key = object(forInfoDictionaryKey: "GOOGLE_SHEETS_API_KEY") as? String, !key.isEmpty {
            print("📱 Using API key from Info.plist")
            return key
        }

        // Fallback for development only - never used in production
        print("📱 Using fallback API key for development")
        // For CI environment, create a placeholder key
        return "DUMMY_API_KEY_FOR_CI_BUILD"
    }

    /// Read a key from the APIKeys.plist file (which should be .gitignored)
    private func apiKeyFromLocalPlist(keyName: String) -> String? {
        // For CI builds, we need to be resilient to missing files
        guard let keyFilePath = path(forResource: "APIKeys", ofType: "plist") else {
            print("⚠️ No APIKeys.plist file found")

            // For CI builds, try using the template file if it exists
            if let templatePath = path(forResource: "APIKeys.plist", ofType: "template") {
                print("📱 Found template file, using it instead")
                guard let plist = NSDictionary(contentsOfFile: templatePath) else {
                    return nil
                }

                return plist[keyName] as? String
            }

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

        print("📱 Successfully loaded API key from APIKeys.plist")
        return apiKey
    }
}

/// Global function for convenience access to the Google Sheets API key
public func getAPIKey() -> String {
    let key = Bundle.main.googleSheetsAPIKey()
    // Check if key looks valid (API keys are usually fairly long)
    if key.count < 10 || key == "DUMMY_API_KEY_FOR_CI_BUILD" {
        print("⚠️ WARNING: API key looks invalid or is using fallback value: \(key.prefix(5))...")
    } else {
        print("✅ API key looks valid (length: \(key.count))")
    }
    return key
}