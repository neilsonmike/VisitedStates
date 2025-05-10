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
            let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(sheetID)/values/Sheet1!A:C?key=\(apiKey)")!
            
            print("🔄 Making direct Google Sheets request for \(state)")
            
            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("⚠️ Google Sheets error: \(error.localizedDescription)")
                    // Use a simple welcome message - don't mention the specific error to users
                    completion("Welcome to \(state)!")
                    return
                }
                
                guard let data = data else {
                    print("⚠️ No data received from Google Sheets")
                    // Use a simple welcome message - don't mention the specific error to users
                    completion("Welcome to \(state)!")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let values = json["values"] as? [[String]] {
                        
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
                            print("📝 Found factoid for \(state) in Google Sheets")
                            
                            // Use the public method to save the factoids
                            self.updateCachedFactoids(for: state, with: stateFactoids)
                            
                            completion(fact)
                        } else {
                            print("📝 No factoids found for \(state) in Google Sheets")
                            // Use a simple welcome message without technical details
                            completion("Welcome to \(state)!")
                        }
                    } else {
                        print("⚠️ Invalid data format from Google Sheets")
                        // Use a simple welcome message - don't expose technical details to users
                        completion("Welcome to \(state)!")
                    }
                } catch {
                    print("⚠️ JSON parsing error: \(error.localizedDescription)")
                    // Use a simple welcome message - don't expose technical details to users
                    completion("Welcome to \(state)!")
                }
            }.resume()
            
            return true // Indicate we handled the request
        }
        
        return false // Continue with normal flow
    }
}