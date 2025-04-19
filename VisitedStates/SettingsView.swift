import SwiftUI
import Combine
import CoreLocation

struct SettingsView: View {
    // Access app dependencies
    @EnvironmentObject var dependencies: AppDependencies
    
    // Environment values
    @Environment(\.presentationMode) var presentationMode
    
    // Local state
    @State private var showingSchemaAlert: Bool = false
    @State private var showEditStates = false
    @State private var showRestoreAlert = false  // For restore defaults confirmation
    @State private var notificationsEnabled = true
    @State private var notifyOnlyNewStates = false
    @State private var stateFillColor: Color = .red
    @State private var stateStrokeColor: Color = .white
    @State private var backgroundColor: Color = .white
    @State private var cancellables = Set<AnyCancellable>()
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    
    var body: some View {
        NavigationView {
            Form {
                // Preferences Section
                Section(header: Text("Preferences")) {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            dependencies.settingsService.notificationsEnabled.send(newValue)
                        }
                    
                    if notificationsEnabled {
                        VStack(alignment: .leading) {
                            Toggle("Notify Only for New States", isOn: $notifyOnlyNewStates)
                                .onChange(of: notifyOnlyNewStates) { _, newValue in
                                    dependencies.settingsService.notifyOnlyNewStates.send(newValue)
                                }
                            
                            // Conditional explainer text
                            Text(notifyOnlyNewStates ?
                                 "You will only be notified if you enter a state you have not visited before" :
                                 "You will get a notification whenever you enter any state")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                                .padding(.leading, 4)
                        }
                    }
                    
                    ColorPicker("State Fill Color", selection: $stateFillColor)
                        .onChange(of: stateFillColor) { _, newValue in
                            dependencies.settingsService.stateFillColor.send(newValue)
                        }
                    
                    ColorPicker("State Border Color", selection: $stateStrokeColor)
                        .onChange(of: stateStrokeColor) { _, newValue in
                            dependencies.settingsService.stateStrokeColor.send(newValue)
                        }
                    
                    ColorPicker("Background Color", selection: $backgroundColor)
                        .onChange(of: backgroundColor) { _, newValue in
                            dependencies.settingsService.backgroundColor.send(newValue)
                        }
                }
                
                // Restore Defaults Section (affects only colors)
                Section {
                    Button("Restore Defaults") {
                        showRestoreAlert = true
                    }
                    .foregroundColor(.red)
                    .alert("Restore Defaults", isPresented: $showRestoreAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Restore", role: .destructive) {
                            dependencies.settingsService.restoreDefaults()
                        }
                    } message: {
                        Text("Are you sure you want to restore the default color selections?")
                    }
                }
                
                // Location Privacy Section
                Section(header: Text("Location Access")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current Permission:")
                            Spacer()
                            Text(locationStatusText)
                                .foregroundColor(locationStatusColor)
                        }
                        
                        Text("VisitedStates uses location to detect when you cross state lines, even when the app is closed. For full functionality after device restarts, 'Always' permission is recommended.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                        
                        Button("Open Location Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // State Editing Section (without header)
                Section {
                    Button("Edit Visited States") {
                        showEditStates.toggle()
                    }
                }
                
                // About Section
                Section {
                    NavigationLink("About VisitedStates", destination: AboutView())
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showEditStates) {
                EditStatesView()
                    .environmentObject(dependencies)
            }
        }
        .onAppear {
            setupSubscriptions()
            updateLocationStatus()
        }
        .onDisappear {
            // When settings view is dismissed, trigger a sync
            dependencies.cloudSyncService.syncToCloud(
                states: dependencies.settingsService.visitedStates.value) { _ in }
            
            cancellables.removeAll()
        }
    }
    
    private var locationStatusText: String {
        switch locationStatus {
        case .authorizedAlways:
            return "Always (Optimal)"
        case .authorizedWhenInUse:
            return "While Using App"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var locationStatusColor: Color {
        switch locationStatus {
        case .authorizedAlways:
            return .green
        case .authorizedWhenInUse:
            return .orange
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .red
        @unknown default:
            return .red
        }
    }
    
    private func updateLocationStatus() {
        // Get the current location authorization status
        locationStatus = dependencies.locationService.authorizationStatus.value
    }
    
    private func setupSubscriptions() {
        // Subscribe to settings changes
        dependencies.settingsService.notificationsEnabled
            .sink { value in
                self.notificationsEnabled = value
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.notifyOnlyNewStates
            .sink { value in
                self.notifyOnlyNewStates = value
            }
            .store(in: &cancellables)
        
        dependencies.settingsService.stateFillColor
            .sink { color in
                self.stateFillColor = color
            }
            .store(in: &cancellables)
        
        dependencies.settingsService.stateStrokeColor
            .sink { color in
                self.stateStrokeColor = color
            }
            .store(in: &cancellables)
        
        dependencies.settingsService.backgroundColor
            .sink { color in
                self.backgroundColor = color
            }
            .store(in: &cancellables)
        
        // Subscribe to location authorization changes
        dependencies.locationService.authorizationStatus
            .sink { status in
                self.locationStatus = status
            }
            .store(in: &cancellables)
    }
}
