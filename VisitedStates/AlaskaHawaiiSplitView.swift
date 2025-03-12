import SwiftUI

struct AHInsetStateView: View {
    let stateName: String
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Text("AHInsetStateView for \(stateName)")
            .environmentObject(settings)
    }
}

struct AlaskaHawaiiSplitView: View {
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        HStack(spacing: 0) {
            AHInsetStateView(stateName: "Alaska")
                .environmentObject(settings)
            Divider()
            AHInsetStateView(stateName: "Hawaii")
                .environmentObject(settings)
        }
    }
}
