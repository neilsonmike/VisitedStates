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
        // View to display Alaska and Hawaii insets clearly separated by a divider
        HStack(spacing: 0) {
            AHInsetStateView(stateName: "Alaska")
            Divider()
            AHInsetStateView(stateName: "Hawaii")
        }
    }
}
