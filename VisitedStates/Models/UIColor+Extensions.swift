import SwiftUI
import UIKit

// Extension to convert between UIColor and SwiftUI Color
extension UIColor {
    convenience init(color: Color) {
        // Use a simpler approach for SwiftUI Color to UIColor conversion
        // That works across iOS versions
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        // Get RGB components using UIKit's representation
        // This approach avoids iOS version-specific APIs
        guard let cgColor = color.cgColor else {
            self.init(red: 0, green: 0, blue: 0, alpha: 1)
            return
        }
        
        let uiColor = UIColor(cgColor: cgColor)
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension Color {
    init(uiColor: UIColor) {
        self.init(red: Double(uiColor.coreImageColor.red), 
                  green: Double(uiColor.coreImageColor.green),
                  blue: Double(uiColor.coreImageColor.blue),
                  opacity: Double(uiColor.coreImageColor.alpha))
    }
}

// Helper extension to get rgba components from UIColor
extension UIColor {
    var coreImageColor: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}