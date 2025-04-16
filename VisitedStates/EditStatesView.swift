import SwiftUI

struct EditStatesView: View {
    @EnvironmentObject var settings: AppSettings
    
    // The user’s LocationManager for final sync
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.presentationMode) var presentationMode
    
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
            List {
                ForEach(allStates, id: \.self) { state in
                    HStack {
                        Text(state)
                        Spacer()
                        if settings.visitedStates.contains(state) {
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
            // This triggers a CloudKit sync after edits are made
            .onDisappear {
                locationManager.syncWithCloudKit()
            }
        }
    }
    
    // Toggle local visitedStates only (no cloud sync here)
    private func toggleState(_ state: String) {
                        if let idx = settings.visitedStates.firstIndex(of: state) {
                            settings.visitedStates.remove(at: idx)
                        } else {
                            settings.visitedStates.append(state)
                        }
    }
}
