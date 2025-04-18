import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    // Add coordinator to handle the presentation lifecycle
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Set the completion handler to handle dismissal
        controller.completionWithItemsHandler = { _, _, _, _ in
            // Optional handling here if needed
        }
        
        // Prevent crash on iPad
        if let popover = controller.popoverPresentationController {
            popover.permittedArrowDirections = .any
            popover.sourceView = UIView()
        }
        
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed for UIActivityViewController
    }
    
    // Coordinator to manage the controller's lifecycle
    class Coordinator: NSObject {
        let parent: ShareSheet
        
        init(_ parent: ShareSheet) {
            self.parent = parent
        }
    }
}
