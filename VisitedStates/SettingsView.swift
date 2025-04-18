import SwiftUI
import Combine

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
    @State private var stateFillColor: Color = .red
    @State private var stateStrokeColor: Color = .white
    @State private var backgroundColor: Color = .white
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            Form {
                // Preferences Section
                Section(header: Text("Preferences")) {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { newValue in
                            dependencies.settingsService.notificationsEnabled.send(newValue)
                        }
                    
                    ColorPicker("State Fill Color", selection: $stateFillColor)
                        .onChange(of: stateFillColor) { newValue in
                            dependencies.settingsService.stateFillColor.send(newValue)
                        }
                    
                    ColorPicker("State Border Color", selection: $stateStrokeColor)
                        .onChange(of: stateStrokeColor) { newValue in
                            dependencies.settingsService.stateStrokeColor.send(newValue)
                        }
                    
                    ColorPicker("Background Color", selection: $backgroundColor)
                        .onChange(of: backgroundColor) { newValue in
                            dependencies.settingsService.backgroundColor.send(newValue)
                        }
                }
                
                // State Editing Section
                Section(header: Text("State Editing")) {
                    Button("Edit Visited States") {
                        showEditStates.toggle()
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
        }
        .onDisappear {
            // When settings view is dismissed, trigger a sync
            dependencies.cloudSyncService.syncToCloud(
                states: dependencies.settingsService.visitedStates.value) { _ in }
            
            cancellables.removeAll()
        }
    }
    
    private func setupSubscriptions() {
        // Subscribe to settings changes
        dependencies.settingsService.notificationsEnabled
            .sink { value in
                self.notificationsEnabled = value
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
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppDependencies.mock())
    }
}
