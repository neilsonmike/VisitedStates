import SwiftUI

struct SplashView: View {
    // When this becomes true, the main content is shown.
    @State private var isActive = false

    var body: some View {
        Group {
            if isActive {
                // Transition to your main ContentView.
                ContentView()
                    .environmentObject(AppSettings.shared)
            } else {
                // Splash screen content.
                VStack {
                    // Replace "AppLogo" with your logo image name from Assets.
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                    Text("Visited States")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .onAppear {
                    // Add any animations you want here.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.isActive = true
                        }
                    }
                }
            }
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
    }
}
