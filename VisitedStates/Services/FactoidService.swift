import Foundation

// Import for API key functions
import UIKit

class FactoidService {
    // Constants for Google Sheets API
    private let sheetID = "1Gg0bGks2nimjX3CEtl4dpfoVSPfG2MWqTqaAe096Jbo"
    // API key should be stored in a secure location, not hardcoded
    private let apiKey: String = {
        return Bundle.main.googleSheetsAPIKey()
    }()
    private var sheetsURL: String {
        return "https://sheets.googleapis.com/v4/spreadsheets/\(sheetID)/values/Sheet1!A:C?key=\(apiKey)"
    }
    
    // For caching
    private var cachedFactoids: [String: [String]] = [:]
    private var lastFetchTime: Date?
    private let cacheInterval: TimeInterval = 3600 // 1 hour cache
    
    // Internal logging with controlled output
    private let enableLogging = false
    private func logDebug(_ message: String) {
        if enableLogging {
            print("FactoidService: \(message)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetches a random factoid for the given state
    /// - Parameters:
    ///   - state: State name (e.g. "California")
    ///   - completion: Callback with the factoid or nil if none found
    func getRandomFactoidFor(state: String, completion: @escaping (String?) -> Void) {
        fetchFactoids { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let factoids):
                // Check if we have facts for this state
                if let stateFacts = factoids[state], !stateFacts.isEmpty {
                    let randomIndex = Int.random(in: 0..<stateFacts.count)
                    let fact = stateFacts[randomIndex]
                    
                    self.logDebug("Found factoid for \(state): \(fact)")
                    completion(fact)
                } else {
                    self.logDebug("No factoids found for \(state)")
                    
                    // Return a generic factoid if no state-specific one is found
                    completion("You're visiting \(state)! Did you know this is one of the 50 United States?")
                }
                
            case .failure(let error):
                self.logDebug("Error fetching factoids: \(error.localizedDescription)")
                
                // Return a generic factoid if there was an error
                completion("You're visiting \(state)! Did you know this is one of the 50 United States?")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Fetches all factoids from Google Sheets or from cache if available
    private func fetchFactoids(completion: @escaping (Result<[String: [String]], Error>) -> Void) {
        // Check cache first
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheInterval,
           !cachedFactoids.isEmpty {
            logDebug("Using cached factoids (last updated \(lastFetch))")
            completion(.success(cachedFactoids))
            return
        }

        // Not in cache, or cache expired - fetch from Google Sheets
        logDebug("Fetching factoids from Google Sheets")

        guard let url = URL(string: sheetsURL) else {
            logDebug("Invalid Google Sheets URL")
            completion(.failure(NSError(domain: "FactoidService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Google Sheets URL"])))
            return
        }

        // Create a request with optimized configuration for compatibility
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0

        // Set basic headers to encourage HTTP/1.1
        let bundleID = Bundle.main.bundleIdentifier ?? "neils.me.VisitedStates"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.10"
        request.setValue("VisitedStates/\(appVersion) (\(bundleID))", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HTTP/1.1", forHTTPHeaderField: "X-HTTP-Version")
        request.setValue("close", forHTTPHeaderField: "Connection")

        // Create a custom session with enhanced compatibility
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "X-HTTP-Version": "HTTP/1.1",
            "Accept": "application/json",
            "Connection": "close"
        ]
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0

        // Use the custom session for this request
        URLSession(configuration: config).dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logDebug("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let data = data else {
                self.logDebug("No data received from Google Sheets API")
                completion(.failure(NSError(domain: "FactoidService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                // Parse JSON response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let values = json["values"] as? [[String]] {
                    
                    self.logDebug("Received \(values.count) rows from Google Sheets")
                    
                    var factoids: [String: [String]] = [:]
                    
                    // Skip header row if it exists
                    let dataRows: [[String]] = values.count > 0 && values[0].count >= 2 && 
                                  (values[0][0] == "State" || values[0][0] == "state") ? 
                                  Array(values.dropFirst()) : values
                    
                    for row in dataRows {
                        if row.count >= 2 {
                            let state = row[0]
                            let fact = row[1]
                            
                            if factoids[state] == nil {
                                factoids[state] = []
                            }
                            
                            factoids[state]?.append(fact)
                        }
                    }
                    
                    // Update cache
                    self.cachedFactoids = factoids
                    self.lastFetchTime = Date()

                    completion(.success(factoids))
                } else {
                    completion(.failure(NSError(domain: "FactoidService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid data format from Google Sheets"])))
                }
            } catch {
                self.logDebug("JSON parsing error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
}