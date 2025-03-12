import SwiftUI

struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @StateObject var settings = AppSettings.shared
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            // Display the MapView with environment object
            MapView(visitedStates: $locationManager.visitedStates)
                .environmentObject(settings)
                .edgesIgnoringSafeArea(.all)
            
            // Settings button only
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showingSettings.toggle()
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.title)
                            .padding(12)
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            NotificationManager.shared.appSettings = settings
        }
        // Present the settings sheet
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(locationManager)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
