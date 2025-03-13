import SwiftUI

struct SettingsView: View {
    // Keep references for color, notifications, etc. in your existing AppSettings
    @EnvironmentObject var settings: AppSettings
    
    // **Important**: Also read locationManager as an environment object
    @EnvironmentObject var locationManager: LocationManager
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingSchemaAlert: Bool = false
    @State private var showEditStates = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Debugging")) {
                    Button("Refresh local data from Cloud") {
                        locationManager.clearLocalData()
                        // Dismiss the settings view
                        presentationMode.wrappedValue.dismiss()
                    }
                    Button("Test Factoid Notification") {
                        NotificationManager.shared.scheduleNotification(for: "TestState")
                    }
                }
                
                Section(header: Text("Preferences")) {
                    Toggle("Enable Notifications", isOn: $settings.notificationsEnabled)
                    ColorPicker("State Fill Color", selection: $settings.stateFillColor)
                    ColorPicker("State Stroke Color", selection: $settings.stateStrokeColor)
                    ColorPicker("Background Color", selection: $settings.backgroundColor)
                    
                    HStack {
                        Text("Speed Threshold (m/s)")
                        Slider(value: $settings.speedThreshold, in: 10...100)
                        Text(String(format: "%.1f", settings.speedThreshold))
                    }
                    
                    HStack {
                        Text("Altitude Threshold (m)")
                        Slider(value: $settings.altitudeThreshold, in: 500...5000)
                        Text(String(format: "%.0f", settings.altitudeThreshold))
                    }
                }
                
                Section {
                    Button("Restore Defaults") {
                        settings.restoreDefaults()
                    }
                    .foregroundColor(.red)
                }

                // New button to edit states
                Section {
                    Button("Edit States") {
                        showEditStates.toggle()
                    }
                }
                
                // New section for About
                Section {
                    NavigationLink("About VisitedStates", destination: AboutView())
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showEditStates) {
                // We pass locationManager's visitedStates
                EditStatesView(visitedStates: $locationManager.visitedStates)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppSettings.shared) // For color pickers, etc.
            .environmentObject(LocationManager())   // For visited states
    }
}
