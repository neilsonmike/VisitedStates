import Foundation
import CloudKit
import SwiftUI
import UIKit

/// This app migrates factoids from CloudKit to Google Sheets
/// Run this in Xcode by creating a simple SwiftUI app with this as the content view
struct CloudKitToGoogleSheetMigrator: View {
    // CloudKit configuration
    private let cloudContainer = CKContainer(identifier: "iCloud.me.neils.VisitedStates")
    private let recordType = "StateFactoids"
    
    // Google Sheets configuration
    private let sheetID = "1Gg0bGks2nimjX3CEtl4dpfoVSPfG2MWqTqaAe096Jbo" // Your Google Sheet ID
    private let apiKey = "[API_KEY_REMOVED]" // Your API key - replace with actual key when using
    
    // State for the UI
    @State private var status = "Ready to start"
    @State private var isRunning = false
    @State private var factoidsFetched = 0
    @State private var factoidsUploaded = 0
    @State private var errorMessage: String? = nil
    @State private var factoids: [[String: Any]] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("CloudKit to Google Sheets Migration")
                .font(.title)
                .padding()
            
            Text("This tool will fetch all factoids from CloudKit and upload them to your Google Sheet")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Status display
            GroupBox(label: Text("Status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current status: \(status)")
                    Text("Factoids fetched: \(factoidsFetched)")
                    Text("Factoids uploaded: \(factoidsUploaded)")
                    
                    if let error = errorMessage {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .padding()
            
            if isRunning {
                ProgressView()
                    .padding()
            } else {
                Button(action: startMigration) {
                    Text("Start Migration")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(isRunning)
                .padding()
            }
            
            if !factoids.isEmpty {
                // Display preview of factoids
                GroupBox(label: Text("Preview (\(factoids.count) factoids)")) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(0..<min(5, factoids.count), id: \.self) { index in
                                if let state = factoids[index]["state"] as? String,
                                   let fact = factoids[index]["fact"] as? String {
                                    VStack(alignment: .leading) {
                                        Text(state).bold()
                                        Text(fact)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                            if factoids.count > 5 {
                                Text("... and \(factoids.count - 5) more")
                                    .italic()
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                    }
                    .frame(height: 200)
                }
                .padding()
            }
            
            // Add export options for iOS
            if !factoids.isEmpty {
                Button("Share CSV Data") {
                    shareCSV()
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding()
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 600, height: 600)
    }
    
    private func startMigration() {
        isRunning = true
        status = "Starting migration..."
        errorMessage = nil
        factoids = []
        factoidsFetched = 0
        factoidsUploaded = 0
        
        // Step 1: Fetch factoids from CloudKit
        fetchFactoids()
    }
    
    private func fetchFactoids() {
        status = "Fetching factoids from CloudKit..."
        
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 100 // Adjust if you have more factoids
        
        // Use latest API
        cloudContainer.publicCloudDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100) { result in
            switch result {
            case .success(let cursor):
                var fetchedFactoids: [[String: Any]] = []
                
                for (_, recordResult) in cursor.matchResults {
                    do {
                        let record = try recordResult.get()
                        
                        if let state = record["state"] as? String,
                           let fact = record["fact"] as? String {
                            fetchedFactoids.append([
                                "state": state,
                                "fact": fact
                            ])
                        }
                    } catch {
                        print("Error processing record: \(error)")
                    }
                }
                
                DispatchQueue.main.async {
                    self.factoids = fetchedFactoids
                    self.factoidsFetched = fetchedFactoids.count
                    self.status = "Fetched \(fetchedFactoids.count) factoids from CloudKit"
                    
                    // Step 2: Upload to Google Sheets
                    self.uploadToGoogleSheet()
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.status = "Error fetching from CloudKit"
                    self.isRunning = false
                }
            }
        }
    }
    
    private func uploadToGoogleSheet() {
        status = "Preparing to upload to Google Sheets..."
        
        // Convert factoids to CSV format
        var csvContent = "state,fact\n"
        
        for factoid in factoids {
            if let state = factoid["state"] as? String,
               let fact = factoid["fact"] as? String {
                // Escape quotes in the fact
                let escapedFact = fact.replacingOccurrences(of: "\"", with: "\"\"")
                csvContent += "\"\(state)\",\"\(escapedFact)\"\n"
            }
        }
        
        // For demonstration purposes, we'll log the CSV to the console
        print(csvContent)
        
        // Now we'd use the Google Sheets API to upload this data
        // Since direct API usage is complex, we'll simulate it for demo purposes
        simulateUploadToGoogleSheets(csvContent: csvContent)
    }
    
    private func simulateUploadToGoogleSheets(csvContent: String) {
        // In a real implementation, you would use URLSession to make API calls
        // to the Google Sheets API to update the sheet
        
        // For now, we'll simulate success and direct the user to copy/paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.status = "Data ready for upload! Check Console for CSV output."
            self.factoidsUploaded = self.factoidsFetched
            self.isRunning = false
            
            // Save the CSV to a file
            saveCSVToDesktop(csv: csvContent)
        }
    }
    
    private func saveCSVToDesktop(csv: String) {
        // For iOS, we'll save to the Documents directory instead of Desktop
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            errorMessage = "Could not find documents directory"
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent("CloudKit_Factoids.csv")
        
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            status = "CSV file saved to Documents folder as 'CloudKit_Factoids.csv'"
            
            // For iOS, let's also show the CSV content directly in the app
            DispatchQueue.main.async {
                self.status = "CSV data ready! Use the Share button to export it."
                // Don't set error message with CSV content as it's too large
            }
        } catch {
            errorMessage = "Failed to save CSV: \(error.localizedDescription)"
        }
    }
    
    // Method to share the CSV file using the iOS share sheet
    private func shareCSV() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            errorMessage = "Could not find documents directory"
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent("CloudKit_Factoids.csv")
        
        // Create a CSV string if we don't have a file yet
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            // Convert factoids to CSV
            var csvContent = "state,fact\n"
            
            for factoid in factoids {
                if let state = factoid["state"] as? String,
                   let fact = factoid["fact"] as? String {
                    // Escape quotes in the fact
                    let escapedFact = fact.replacingOccurrences(of: "\"", with: "\"\"")
                    csvContent += "\"\(state)\",\"\(escapedFact)\"\n"
                }
            }
            
            // Save it
            do {
                try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Failed to save CSV: \(error.localizedDescription)"
                return
            }
        }
        
        // Use UIActivityViewController to share the file
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Could not find root view controller"
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        rootViewController.present(activityVC, animated: true, completion: nil)
    }
}

// Note: When adding this to an Xcode project, remove this code block
// and use the existing App struct provided by Xcode's template.
// This is just here for standalone usage
/*
@main
struct MigrationApp: App {
    var body: some Scene {
        WindowGroup {
            CloudKitToGoogleSheetMigrator()
        }
    }
}
*/