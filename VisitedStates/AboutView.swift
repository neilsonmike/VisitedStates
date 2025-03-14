import SwiftUI

struct AboutView: View {
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 20) {


            Text("VisitedStates")
                .font(.custom("DoHyeon-Regular", size: 28))
                .foregroundColor(.red)

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundColor(.gray)

            Divider()
                .padding(.vertical, 20)

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

            Text("This app was designed and developed entirely through collaboration with AI, demonstrating what’s possible for non-coding product owners and business analysts. No code in this app is human written.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding()
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
