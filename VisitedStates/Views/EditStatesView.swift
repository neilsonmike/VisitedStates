import SwiftUI
import Combine

struct EditStatesView: View {
    // Dependencies
    @EnvironmentObject var dependencies: AppDependencies
    @Environment(\.presentationMode) var presentationMode
    
    // Local state
    @State private var visitedStates: [String] = []
    @State private var gpsVisitedStates: [String] = []
    @State private var cancellables = Set<AnyCancellable>()
    
    // For example, your 51 states (including DC)
    private let allStates = [
        "Alabama", "Alaska", "Arizona", "Arkansas", "California",
        "Colorado", "Connecticut", "Delaware", "District of Columbia", "Florida",
        "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana",
        "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine",
        "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi",
        "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
        "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota",
        "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island",
        "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah",
        "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin",
        "Wyoming"
    ]

    var body: some View {
        NavigationView {
            VStack {
                // Explanation text at the top
                Text("States in bold were detected by GPS.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                List {
                    ForEach(allStates, id: \.self) { state in
                        HStack {
                            // Make text bold if it was GPS-visited
                            if gpsVisitedStates.contains(state) {
                                Text(state)
                                    .fontWeight(.bold)
                            } else {
                                Text(state)
                                    .fontWeight(.regular)
                            }
                            
                            Spacer()
                            
                            if visitedStates.contains(state) {
                                // Show a simple checkmark if visited
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        // Make row tappable
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleState(state)
                        }
                    }
                }
            }
            .navigationTitle("Edit States")
            .toolbar {
                // Provide a Done button
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            // The key change: upon dismiss (swipe down or Done), do one CloudKit sync
            .onDisappear {
                syncWithCloudKit()
            }
            .onAppear {
                // Important: Setup subscription to get the current state list
                setupSubscriptions()
                
                // Get states that were visited via GPS
                loadGPSVisitedStates()
            }
        }
    }
    
    private func setupSubscriptions() {
        // Subscribe to visited states changes from the settings service
        dependencies.settingsService.visitedStates
            .sink { states in
                self.visitedStates = states
                print("EditStatesView received states: \(states)")
            }
            .store(in: &cancellables)
    }
    
    private func loadGPSVisitedStates() {
        // Get all GPS-verified states from the service
        let allGPSStates = dependencies.settingsService.getAllGPSVerifiedStates()
        
        // Extract just the state names for states that were GPS verified
        gpsVisitedStates = allGPSStates
            .filter { $0.wasEverVisited }
            .map { $0.stateName }
        
        print("GPS-visited states: \(gpsVisitedStates)")
    }
    
    // Toggle local visitedStates only (no cloud sync here)
    private func toggleState(_ state: String) {
        if visitedStates.contains(state) {
            // Remove if already visited
            var updatedStates = visitedStates
            if let index = updatedStates.firstIndex(of: state) {
                updatedStates.remove(at: index)
                dependencies.settingsService.setVisitedStates(updatedStates)
                
                // If removing Alaska or Hawaii, refresh colors
                if state == "Alaska" || state == "Hawaii" {
                    forceRefreshColors()
                }
            }
        } else {
            // Add if not visited
            var updatedStates = visitedStates
            updatedStates.append(state)
            dependencies.settingsService.setVisitedStates(updatedStates)
            
            // If adding Alaska or Hawaii, refresh colors
            if state == "Alaska" || state == "Hawaii" {
                forceRefreshColors()
            }
        }
    }
    
    // Force a refresh of color values by sending the current value through the publisher
    private func forceRefreshColors() {
        // Get current colors
        let fillColor = dependencies.settingsService.stateFillColor.value
        let strokeColor = dependencies.settingsService.stateStrokeColor.value
        let bgColor = dependencies.settingsService.backgroundColor.value
        
        // Re-send them through publishers to trigger updates
        dependencies.settingsService.stateFillColor.send(fillColor)
        dependencies.settingsService.stateStrokeColor.send(strokeColor)
        dependencies.settingsService.backgroundColor.send(bgColor)
        
        print("🎨 Forced color refresh - fill: \(fillColor), stroke: \(strokeColor)")
    }
    
    // Sync with CloudKit
    private func syncWithCloudKit() {
        dependencies.cloudSyncService.syncToCloud(
            states: dependencies.settingsService.visitedStates.value) { result in
                switch result {
                case .success:
                    print("Successfully synced states to CloudKit after editing")
                case .failure(let error):
                    print("Failed to sync states to CloudKit: \(error.localizedDescription)")
                }
            }
    }
}

struct EditStatesView_Previews: PreviewProvider {
    static var previews: some View {
        EditStatesView()
            .environmentObject(AppDependencies.mock())
    }
}
