import Foundation

// Simplified extension to add Google Sheets integration for factoids
extension NotificationService {
    
    /// Helper method to determine if we should use Google Sheets
    /// This can be used in NotificationService.swift to choose the data source
    func shouldUseGoogleSheets() -> Bool {
        // Using Google Sheets in both debug and production builds
        return true
    }
    
    /// Add this method to NotificationService.swift to enable Google Sheets
    /// Place it at the start of fetchFactoidWithNetworkPriority
    func checkAndUseGoogleSheets(for state: String, completion: @escaping (String?) -> Void) -> Bool {
        if shouldUseGoogleSheets() {
            // Make direct Google Sheets request without FactoidService
            let sheetID = "1Gg0bGks2nimjX3CEtl4dpfoVSPfG2MWqTqaAe096Jbo" // Use your Sheet ID
            // API key should be stored in a secure location, not hardcoded
            let apiKey = getAPIKey()

            // Create URL request to properly identify app bundle ID
            let urlString = "https://sheets.googleapis.com/v4/spreadsheets/\(sheetID)/values/Sheet1!A:C?key=\(apiKey)"
            guard let url = URL(string: urlString) else {
                // Handle invalid URL
                if let cachedFactoid = getCachedFactoid(for: state) {
                    completion(cachedFactoid)
                } else {
                    completion("Welcome to \(state)!")
                }
                return true
            }

            // Create a proper URLRequest to ensure bundle ID is included
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            // Add additional request configuration to help with network issues
            request.timeoutInterval = 15.0 // Increase timeout to 15 seconds
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData // Force fresh request

            // Set User-Agent to include app bundle ID
            let bundleID = Bundle.main.bundleIdentifier ?? "neils.me.VisitedStates"
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.10"
            request.setValue("VisitedStates/\(appVersion) (\(bundleID))", forHTTPHeaderField: "User-Agent")

            // Add X-iOS-Bundle-Identifier header to explicitly communicate bundle ID
            request.setValue(bundleID, forHTTPHeaderField: "X-iOS-Bundle-Identifier")

            // Add standard headers to improve compatibility
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            // Try to force HTTP/1.1 to avoid QUIC protocol issues
            request.setValue("HTTP/1.1", forHTTPHeaderField: "X-HTTP-Version")

            // Create a custom URLSession with modified configuration to avoid QUIC issues
            let config = URLSessionConfiguration.ephemeral // Use ephemeral session to avoid any cached QUIC connections

            // Set headers to encourage HTTP/1.1
            config.httpAdditionalHeaders = [
                "X-HTTP-Version": "HTTP/1.1",
                "Accept": "application/json",
                "Connection": "close" // Discourage keep-alive which might trigger HTTP/2
            ]

            // Limit connections to avoid complex protocol negotiation
            config.httpMaximumConnectionsPerHost = 1

            // Set a reasonable timeout
            config.timeoutIntervalForRequest = 15.0
            config.timeoutIntervalForResource = 30.0

            // Use custom session for this request
            URLSession(configuration: config).dataTask(with: request) { [weak self] data, _, error in
                guard let self = self else { return }

                // Check for errors first
                if error != nil {
                    // Fall back to cached data on network error
                    if let cachedFactoid = self.getCachedFactoid(for: state) {
                        self.factoidOriginLog[state] = "Cache (after network error)"

                        // Log source for debugging
                        print("📚 Factoid for \(state) sourced from: Cache (after network error)")
                        print("📝 Using cached factoid: \(cachedFactoid)")

                        completion(cachedFactoid)
                    } else {
                        self.factoidOriginLog[state] = "Default (after network error)"

                        // Log source for debugging
                        print("📚 Factoid for \(state) sourced from: Default (after network error)")

                        completion("Welcome to \(state)!")
                    }
                    return
                }

                // Ensure we have data
                guard let data = data else {
                    // No data received, try cache
                    if let cachedFactoid = self.getCachedFactoid(for: state) {
                        completion(cachedFactoid)
                    } else {
                        completion("Welcome to \(state)!")
                    }
                    return
                }

                do {
                    // Parse JSON response
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check for error object first (common Google API pattern)
                        if json["error"] != nil {
                            // API returned an error - use cache
                            if let cachedFactoid = self.getCachedFactoid(for: state) {
                                self.factoidOriginLog[state] = "Cache (after API error)"
                                completion(cachedFactoid)
                            } else {
                                self.factoidOriginLog[state] = "Default (after API error)"
                                completion("Welcome to \(state)!")
                            }
                            return
                        }

                        // No error, try to process values
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

                                // Save for future use
                                self.updateCachedFactoids(for: state, with: stateFactoids)
                                self.factoidOriginLog[state] = "Google Sheets"

                                // Log factoid source for debugging
                                print("📚 Factoid for \(state) sourced from: Google Sheets API (live)")
                                print("📝 Selected: \(fact)")

                                completion(fact)
                            } else {
                                // No factoids found for this state
                                if let cachedFactoid = self.getCachedFactoid(for: state) {
                                    self.factoidOriginLog[state] = "Cache (no matching state)"

                                    // Log source for debugging
                                    print("📚 Factoid for \(state) sourced from: Cache (no matching state in API)")
                                    print("📝 Using cached factoid: \(cachedFactoid)")

                                    completion(cachedFactoid)
                                } else {
                                    self.factoidOriginLog[state] = "Default (no matching state)"

                                    // Log source for debugging
                                    print("📚 Factoid for \(state) sourced from: Default (no matching state)")

                                    completion("Welcome to \(state)!")
                                }
                            }
                        } else {
                            // Missing values array
                            if let cachedFactoid = self.getCachedFactoid(for: state) {
                                self.factoidOriginLog[state] = "Cache (missing values array)"
                                completion(cachedFactoid)
                            } else {
                                self.factoidOriginLog[state] = "Default (missing values array)"
                                completion("Welcome to \(state)!")
                            }
                        }
                    } else {
                        // Invalid JSON format
                        if let cachedFactoid = self.getCachedFactoid(for: state) {
                            self.factoidOriginLog[state] = "Cache (invalid JSON)"
                            completion(cachedFactoid)
                        } else {
                            self.factoidOriginLog[state] = "Default (invalid JSON)"
                            completion("Welcome to \(state)!")
                        }
                    }
                } catch {
                    // JSON parsing error
                    if let cachedFactoid = self.getCachedFactoid(for: state) {
                        self.factoidOriginLog[state] = "Cache (JSON parsing error)"
                        completion(cachedFactoid)
                    } else {
                        self.factoidOriginLog[state] = "Default (JSON parsing error)"
                        completion("Welcome to \(state)!")
                    }
                }
            }.resume()

            return true // Indicate we handled the request
        }

        return false // Continue with normal flow
    }
}