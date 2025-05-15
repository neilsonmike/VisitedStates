import Foundation
import UIKit

// Google Sheets integration for factoids
extension NotificationService {

    /// Helper method to determine if we should use Google Sheets
    func shouldUseGoogleSheets() -> Bool {
        return true
    }
    
    // No extra debug logging methods needed

    /// Add this method to NotificationService.swift to enable Google Sheets
    /// Place it at the start of fetchFactoidWithNetworkPriority
    func checkAndUseGoogleSheets(for state: String, completion: @escaping (String?) -> Void) -> Bool {
        if shouldUseGoogleSheets() {
            print("🌐 Attempting to fetch factoid from Google Sheets for \(state)")
            // Make direct Google Sheets request
            let sheetID = "1Gg0bGks2nimjX3CEtl4dpfoVSPfG2MWqTqaAe096Jbo"
            let apiKey = getAPIKey()

            // Verify API key and Sheet ID look valid
            if apiKey.count < 20 || apiKey == "YOUR_API_KEY_HERE" || apiKey == "DUMMY_API_KEY_FOR_CI_BUILD" {
                print("🌐 Google Sheets API error: Invalid API key")
                // Fall back to cached data on invalid API key
                if let cachedFactoid = getCachedFactoid(for: state) {
                    completion(cachedFactoid)
                } else {
                    completion("Enjoy your stay!")
                }
                return true
            }
            
            if sheetID.isEmpty || sheetID == "YOUR_SHEET_ID_HERE" {
                print("🌐 Google Sheets API error: Invalid Sheet ID")
                // Fall back to cached data on invalid sheet ID
                if let cachedFactoid = getCachedFactoid(for: state) {
                    completion(cachedFactoid)
                } else {
                    completion("Enjoy your stay!")
                }
                return true
            }
            
            // Get bundle ID for use in API request
            let bundleID = Bundle.main.bundleIdentifier ?? "neils.me.VisitedStates"
            
            // Create standard Google Sheets API URL 
            // The API key should be restricted in the Google Cloud Console to your app's bundle ID
            // iOS apps are identified by the X-Ios-Bundle-Identifier header, not URL parameters
            let urlString = "https://sheets.googleapis.com/v4/spreadsheets/\(sheetID)/values/Sheet1!A:C?key=\(apiKey)"

            guard let url = URL(string: urlString) else {
                print("🌐 Google Sheets API error: Invalid URL")
                // Handle invalid URL
                if let cachedFactoid = getCachedFactoid(for: state) {
                    completion(cachedFactoid)
                } else {
                    completion("Enjoy your stay!")
                }
                return true
            }

            // Create a proper URLRequest with needed headers
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15.0
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            // Set User-Agent with app version information
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.1"
            request.setValue("VisitedStates/\(appVersion) (\(bundleID))", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            // CRITICAL FIX: Use the official Google-recommended headers for iOS apps
            // Google documentation states to use X-Ios-Bundle-Identifier for API key restrictions
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
            
            // Add the standard Apple recommended device headers
            request.setValue(UIDevice.current.model, forHTTPHeaderField: "X-Device-Model")
            request.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "X-Device-System-Version")

            // Create a custom URLSession with modified configuration
            let config = URLSessionConfiguration.ephemeral
            config.httpAdditionalHeaders = [
                "Accept": "application/json",
                "Connection": "close",
                "X-Ios-Bundle-Identifier": bundleID, // Google's recommended header for API key restrictions
                "X-Device-Model": UIDevice.current.model,
                "X-Device-System-Version": UIDevice.current.systemVersion
            ]
            config.timeoutIntervalForRequest = 15.0
            config.timeoutIntervalForResource = 30.0
            
            // Make the request
            URLSession(configuration: config).dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                // Check for network errors
                if let error = error {
                    print("🌐 Google Sheets API error: \(error.localizedDescription)")
                    // Fall back to cached data on network error
                    if let cachedFactoid = self.getCachedFactoid(for: state) {
                        self.factoidOriginLog[state] = "Cache (after network error)"
                        completion(cachedFactoid)
                    } else {
                        self.factoidOriginLog[state] = "Simple welcome (after network error)"
                        completion("Enjoy your stay!")
                    }
                    return
                }
                
                // Check HTTP response code
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    
                    if statusCode != 200 {
                        print("🌐 Google Sheets API error: HTTP status \(statusCode)")
                        
                        // Fall back to cached data on HTTP error
                        if let cachedFactoid = self.getCachedFactoid(for: state) {
                            self.factoidOriginLog[state] = "Cache (after HTTP error \(statusCode))"
                            completion(cachedFactoid)
                        } else {
                            self.factoidOriginLog[state] = "Simple welcome (after HTTP error \(statusCode))"
                            completion("Enjoy your stay!")
                        }
                        return
                    }
                }

                // Ensure we have data
                guard let data = data else {
                    // No data received, try cache
                    if let cachedFactoid = self.getCachedFactoid(for: state) {
                        completion(cachedFactoid)
                    } else {
                        completion("Enjoy your stay!")
                    }
                    return
                }

                do {
                    // Parse JSON response
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check for error object first (common Google API pattern)
                        if let error = json["error"] as? [String: Any] {
                            // Extract detailed error info if available
                            let errorMessage = (error["message"] as? String) ?? "Unknown error"
                            _ = (error["code"] as? Int) ?? 0
                            print("🌐 Google Sheets API error: \(errorMessage)")
                            
                            // API returned an error - use cache
                            if let cachedFactoid = self.getCachedFactoid(for: state) {
                                self.factoidOriginLog[state] = "Cache (after API error)"
                                completion(cachedFactoid)
                            } else {
                                self.factoidOriginLog[state] = "Simple welcome (after API error)"
                                completion("Enjoy your stay!")
                            }
                            return
                        }

                        // Process factoid values
                        if let values = json["values"] as? [[String]] {
                            // Find factoids for this state
                            var stateFactoids: [String] = []

                            // Skip header row if it exists
                            let dataRows = values.count > 0 && values[0].count >= 2 &&
                                           (values[0][0] == "State" || values[0][0] == "state") ?
                                           Array(values.dropFirst()) : values

                            // Process data rows
                            for row in dataRows {
                                if row.count >= 2 && row[0] == state {
                                    stateFactoids.append(row[1])
                                }
                            }

                            if !stateFactoids.isEmpty {
                                // Get a random factoid
                                let randomIndex = Int.random(in: 0..<stateFactoids.count)
                                let fact = stateFactoids[randomIndex]
                                print("📚 Found factoid for \(state)")

                                // Store in UserDefaults directly to guarantee persistence
                                UserDefaults.standard.set(fact, forKey: "DIRECT_FACTOID_\(state)")
                                UserDefaults.standard.synchronize()

                                // Update the cache for future use
                                self.updateCachedFactoids(for: state, with: stateFactoids)
                                self.factoidOriginLog[state] = "Google Sheets API (live)"

                                // Add source indicator in debug builds only
                                #if DEBUG
                                    let debugFact = "[LIVE] \(fact)"
                                    completion(debugFact)
                                #else
                                    // Production builds get the fact without a prefix
                                    completion(fact)
                                #endif
                            } else {
                                // No factoids found for this state
                                print("📚 No factoids found in Google Sheets for \(state)")
                                if let cachedFactoid = self.getCachedFactoid(for: state) {
                                    self.factoidOriginLog[state] = "Cache (no matching state)"
                                    completion(cachedFactoid)
                                } else {
                                    self.factoidOriginLog[state] = "Simple welcome (no matching state)"
                                    completion("Enjoy your stay!")
                                }
                            }
                        } else {
                            // Missing values array
                            if let cachedFactoid = self.getCachedFactoid(for: state) {
                                self.factoidOriginLog[state] = "Cache (missing values array)"
                                completion(cachedFactoid)
                            } else {
                                self.factoidOriginLog[state] = "Simple welcome (missing values array)"
                                completion("Enjoy your stay!")
                            }
                        }
                    } else {
                        // Invalid JSON format
                        if let cachedFactoid = self.getCachedFactoid(for: state) {
                            self.factoidOriginLog[state] = "Cache (invalid JSON)"
                            completion(cachedFactoid)
                        } else {
                            self.factoidOriginLog[state] = "Simple welcome (invalid JSON)"
                            completion("Enjoy your stay!")
                        }
                    }
                } catch {
                    // JSON parsing error
                    if let cachedFactoid = self.getCachedFactoid(for: state) {
                        self.factoidOriginLog[state] = "Cache (JSON parsing error)"
                        completion(cachedFactoid)
                    } else {
                        self.factoidOriginLog[state] = "Simple welcome (JSON parsing error)"
                        completion("Enjoy your stay!")
                    }
                }
            }.resume()

            return true // Indicate we handled the request
        }

        return false // Continue with normal flow
    }
}