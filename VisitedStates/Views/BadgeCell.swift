import SwiftUI

/// A cell displaying a badge with progress indicator
struct BadgeCell: View {
    let badge: AchievementBadge
    let isEarned: Bool
    let progress: Float // 0.0-1.0
    let size: CGFloat

    init(badge: AchievementBadge, isEarned: Bool, progress: Float, size: CGFloat = 60) {
        self.badge = badge
        self.isEarned = isEarned
        self.progress = progress
        self.size = size
    }

    var body: some View {
        ZStack {
            // Outer white ring
            Circle()
                .fill(Color.white)
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.2), radius: 3, x: 1, y: 1)

            // Inner colored circle
            Circle()
                .fill(isEarned ? badge.color : Color.gray.opacity(0.5))
                .frame(width: size * 0.85, height: size * 0.85) // Larger inner circle with thinner white border

            // Special handling for different badge types
            if badge.category == .milestone {
                // Number icon for milestone badges
                Text(badge.id == "newbie" ? "1" :
                    badge.id == "explorer" ? "10" :
                    badge.id == "journeyer" ? "20" :
                    badge.id == "voyager" ? "30" :
                    badge.id == "adventurer" ? "40" :
                    badge.id == "completionist" ? "50" : "")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.white)
            }
            // Custom text for Four Letter Words badge
            else if badge.id == "four_letter_words" {
                Text("$@#&!")
                    .font(.system(size: size * 0.25, weight: .bold))
                    .foregroundColor(.white)
            }
            // Use icon for all other badges
            else {
                Image(systemName: badge.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.5, height: size * 0.5)
                    .foregroundColor(.white)
            }

            // Progress ring (only for unearned badges)
            if !isEarned && progress > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: size * 0.95, height: size * 0.95) // Adjusted to match new size

                // Progress percentage
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(3)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .offset(y: size * 0.4)
            }

            // If the badge is earned, show a checkmark indicator
            if isEarned {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 24))
                }
                .offset(x: size * 0.3, y: -size * 0.3)
            }
        }
        .padding(5)
    }
}

/// Preview provider for BadgeCell
struct BadgeCell_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                // Earned badge
                BadgeCell(
                    badge: AchievementBadgeProvider.allBadges[0],
                    isEarned: true,
                    progress: 1.0
                )

                // In progress badge - 50%
                BadgeCell(
                    badge: AchievementBadgeProvider.allBadges[1],
                    isEarned: false,
                    progress: 0.5
                )

                // Not started badge
                BadgeCell(
                    badge: AchievementBadgeProvider.allBadges[2],
                    isEarned: false,
                    progress: 0.0
                )
            }

            // Different badge types
            HStack(spacing: 20) {
                BadgeCell(
                    badge: AchievementBadgeProvider.allBadges[0], // Milestone
                    isEarned: true,
                    progress: 1.0
                )

                BadgeCell(
                    badge: AchievementBadgeProvider.allBadges[6], // Geographic
                    isEarned: true,
                    progress: 1.0
                )

                BadgeCell(
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