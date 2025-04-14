import SwiftUI

struct SettingsView: View {
    // References for app settings and the LocationManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var locationManager: LocationManager
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingSchemaAlert: Bool = false
    @State private var showEditStates = false
    @State private var showRestoreAlert = false  // For restore defaults confirmation
    
    var body: some View {
        NavigationView {
            Form {
                // Preferences Section
                Section(header: Text("Preferences")) {
                    Toggle("Enable Notifications", isOn: $settings.notificationsEnabled)
                    ColorPicker("State Fill Color", selection: $settings.stateFillColor)
                    ColorPicker("State Stroke Color", selection: $settings.stateStrokeColor)
                    ColorPicker("Background Color", selection: $settings.backgroundColor)
                }
                
                // State Editing and Purchases Section
                Section(header: Text("State Editing")) {
                    if settings.hasUnlockedStateEditing {
                        // If the feature is unlocked, only show the edit button.
                        Button("Edit Visited States") {
                            showEditStates.toggle()
                        }
                    } else {
                        // If not unlocked, show both the Unlock button and a Restore Purchase option.
                        Button("Unlock State Editing") {
                            Task {
                                await settings.purchaseStateEditing()
                            }
                        }
                        .foregroundColor(.blue)
                        
                        Button("Restore Purchase") {
                            Task {
                                await IAPManager.shared.restorePurchases()
                                // Update your settings once restored.
                                settings.updatePurchasedProducts()
                            }
                        }
                        .foregroundColor(.blue)
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
                            settings.restoreDefaults()
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
                EditStatesView(visitedStates: $locationManager.visitedStates)
                    .environmentObject(settings)
                    .environmentObject(locationManager)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppSettings.shared)
            .environmentObject(LocationManager())
    }
}
