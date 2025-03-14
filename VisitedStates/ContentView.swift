import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @StateObject var settings = AppSettings.shared
    @State private var showingSettings = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    
    var body: some View {
        ZStack {
            // Display the MapView with environment object
            MapView(visitedStates: $locationManager.visitedStates)
                .environmentObject(settings)
                .edgesIgnoringSafeArea(.all)
            
            // Settings and share buttons
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Button(action: {
                            let renderer = ImageRenderer(content:
                                MapView(visitedStates: $locationManager.visitedStates)
                                    .environmentObject(settings)
                                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                            )
                            renderer.scale = UIScreen.main.scale

                            if let uiImage = renderer.uiImage {
                                shareItems = [uiImage, "Check out my visited states!"]
                                showShareSheet = true
                            }
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }

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
                    }
                    .padding(.bottom, 16)
                    .padding(.trailing, 16)
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
        .sheet(isPresented: Binding(
            get: { showShareSheet },
            set: { showShareSheet = $0 }
        )) {
            ShareSheet(activityItems: shareItems)
        }
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
