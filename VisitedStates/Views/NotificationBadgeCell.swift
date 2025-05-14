import SwiftUI

/// A wrapper for BadgeCell that suppresses the checkmark indicator
/// specifically designed for use in notification views
struct NotificationBadgeCell: View {
    let badge: AchievementBadge
    let isEarned: Bool
    let progress: Float
    let size: CGFloat
    
    init(badge: AchievementBadge, isEarned: Bool, progress: Float, size: CGFloat = 60) {
        self.badge = badge
        self.isEarned = isEarned
        self.progress = progress
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Badge circle background
            Circle()
                .fill(isEarned ? badge.color : Color.gray.opacity(0.3))
                .frame(width: size, height: size)
            
            // Badge icon
            Image(systemName: badge.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 1, y: 1)
            
            // Progress ring (only for unearned badges)
            if !isEarned && progress > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 5, height: size + 5)
                
                // Progress percentage
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(3)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .offset(y: size * 0.4)
            }
            
            // Note: The checkmark is intentionally omitted for the notification view
            // to create a cleaner, more streamlined appearance
        }
        .padding(5)
    }
}

/// Preview provider for NotificationBadgeCell
struct NotificationBadgeCell_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                // Earned badge
                NotificationBadgeCell(
                    badge: AchievementBadgeProvider.allBadges[0],
                    isEarned: true,
                    progress: 1.0
                )
                
                // In progress badge - 50%
                NotificationBadgeCell(
                    badge: AchievementBadgeProvider.allBadges[1],
                    isEarned: false,
                    progress: 0.5
                )
                
                // Not started badge
                NotificationBadgeCell(
                    badge: AchievementBadgeProvider.allBadges[2],
                    isEarned: false,
                    progress: 0.0
                )
            }
            
            // Different badge types
            HStack(spacing: 20) {
                NotificationBadgeCell(
                    badge: AchievementBadgeProvider.allBadges[0], // Milestone
                    isEarned: true,
                    progress: 1.0
                )
                
                NotificationBadgeCell(
                    badge: AchievementBadgeProvider.allBadges[6], // Geographic
                    isEarned: true,
                    progress: 1.0
                )
                
                NotificationBadgeCell(
                    badge: AchievementBadgeProvider.allBadges[10], // Special
                    isEarned: true,
                    progress: 1.0
                )
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}