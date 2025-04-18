import SwiftUI

struct AHInsetStateView: View {
    let stateName: String
    @EnvironmentObject var dependencies: AppDependencies

    var body: some View {
        Text("AHInsetStateView for \(stateName)")
            .environmentObject(dependencies)
    }
}

struct AlaskaHawaiiSplitView: View {
    @EnvironmentObject var dependencies: AppDependencies
    
    var body: some View {
        // View to display Alaska and Hawaii insets clearly separated by a divider
        HStack(spacing: 0) {
            AHInsetStateView(stateName: "Alaska")
            Divider()
            AHInsetStateView(stateName: "Hawaii")
        }
    }
}
