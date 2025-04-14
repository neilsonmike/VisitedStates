import SwiftUI

struct SettingsView: View {
    // Keep references for color, notifications, etc. in your existing AppSettings
    @EnvironmentObject var settings: AppSettings
    
    // Also read locationManager as an environment object
    @EnvironmentObject var locationManager: LocationManager
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingSchemaAlert: Bool = false
    @State private var showEditStates = false
    @State private var showRestoreAlert = false  // For the "Restore Defaults" alert
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Preferences
                Section(header: Text("PREFERENCES")) {
                    Toggle("Enable Notifications", isOn: $settings.notificationsEnabled)
                    ColorPicker("State Fill Color", selection: $settings.stateFillColor)
                    ColorPicker("State Stroke Color", selection: $settings.stateStrokeColor)
                    ColorPicker("Background Color", selection: $settings.backgroundColor)
                }
                
                // MARK: - Restore Defaults
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
                
                // MARK: - State Editing
                Section {
                    if settings.hasUnlockedStateEditing {
                        // The user already has editing unlocked
                        Button("Edit Visited States") {
                            showEditStates.toggle()
                        }
                    } else {
                        // The user has not purchased yet
                        Button("Unlock State Editing") {
                            Task {
                                await AppSettings.shared.purchaseStateEditing()
                            }
                        }
                        Button("Restore Purchase") {
                            Task {
                                // Attempt to restore purchases
                                await IAPManager.shared.restorePurchases()
                                // Then update the local purchased state
                                settings.updatePurchasedProducts()
                            }
                        }
                    }
                }
                
                // MARK: - About
                Section {
                    NavigationLink("About VisitedStates", destination: AboutView())
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showEditStates) {
                // We pass locationManager's visitedStates to EditStatesView
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
