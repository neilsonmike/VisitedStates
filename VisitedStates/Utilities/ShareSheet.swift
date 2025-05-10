import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var completion: (() -> Void)? = nil
    
    // Add coordinator to handle the presentation lifecycle
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Set the completion handler to handle dismissal
        controller.completionWithItemsHandler = { _, _, _, _ in
            self.completion?()
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

// Simple wrapper for easier usage
extension ShareSheet {
    init(items: [Any], completion: (() -> Void)? = nil) {
        self.activityItems = items
        self.completion = completion
    }
    
    // Helper method to present a share sheet programmatically
    func share() {
        // Find the current window scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            print("Cannot find root view controller")
            return
        }
        
        // Create a UIActivityViewController directly
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Set the completion handler if provided
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            self.completion?()
        }
        
        // Handle iPad presentation
        if let popover = activityVC.popoverPresentationController {
            // Find center of the screen
            if let window = windowScene.windows.first {
                let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
                popover.sourceView = window
                popover.sourceRect = CGRect(origin: center, size: CGSize(width: 0, height: 0))
                popover.permittedArrowDirections = []
            }
        }
        
        // Present the view controller
        DispatchQueue.main.async {
            // Find the top-most presented controller
            var topController = rootVC
            while let presentedVC = topController.presentedViewController {
                topController = presentedVC
            }
            
            topController.present(activityVC, animated: true)
        }
    }
}
