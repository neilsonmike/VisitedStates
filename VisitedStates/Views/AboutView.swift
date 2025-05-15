import SwiftUI

struct AboutView: View {
    // For dismissing the view
    @Environment(\.presentationMode) var presentationMode
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.1"
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Create a spacer that pushes content down
                    Spacer()
                    
                    // Main content centered in the remaining space
                    VStack(spacing: 20) {
                        // Replace text with logo image
                        Image("VisitedStatesLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width * 0.7) // 70% of screen width

                        VStack(spacing: 4) {
                            Text("Version \(appVersion)")
                                .font(.subheadline)
                                .foregroundColor(.gray)

                            #if DEBUG
                            // This will ONLY show in debug/development builds
                            Text("Development Build")
                                .font(.subheadline)
                                .foregroundColor(.red)
                            #endif
                        }

                        Divider()
                            .padding(.vertical, 10)

                        VStack(spacing: 8) {
                            Text("Created by Mike Neilson")
                                .font(.footnote)

                            Link("Bluesky: @neils.me", destination: URL(string: "https://bsky.app/profile/neils.me")!)
                                .font(.footnote)
                                .foregroundColor(.blue)
                                .underline()

                            Link("GitHub: neilsonmike", destination: URL(string: "https://github.com/neilsonmike")!)
                                .font(.footnote)
                                .foregroundColor(.blue)
                                .underline()

                            Text("©2025 Mike Neilson. All rights reserved.")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .foregroundColor(.gray)

                        Text("This app was designed and developed entirely through collaboration with AI as a test of the possibilities of pairing a product owner with an AI developer. No original code in this app is human written.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.horizontal)
                    
                    // Create another spacer to push content up, creating center alignment
                    Spacer()
                }
            }
            .navigationBarTitle("About", displayMode: .inline)
            // Using the modern toolbar API with Done button in top-right (iOS standard)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .background(Color(.systemBackground))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            print("AboutView appeared")
        }
        .onDisappear {
            print("AboutView disappeared")
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
