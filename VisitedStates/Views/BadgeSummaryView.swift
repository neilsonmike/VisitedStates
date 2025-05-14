import SwiftUI

/// View for displaying a summary of newly earned badges
struct BadgeSummaryView: View {
    let newBadges: [AchievementBadge]
    @Binding var isPresented: Bool
    @State private var selectedBadge: AchievementBadge? = nil
    @Binding var showBadges: Bool
    
    // Determine columns based on badge count
    private var columns: [GridItem] {
        if newBadges.count == 1 {
            // Single centered badge
            return [GridItem(.flexible())]
        } else if newBadges.count <= 6 {
            // 2 badges per row for 2-6 badges
            return [
                GridItem(.flexible()),
                GridItem(.flexible())
            ]
        } else {
            // 3 badges per row for 7+ badges
            return [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ]
        }
    }
    
    // Determine badge size based on count
    private var badgeSize: CGFloat {
        if newBadges.count == 1 {
            return 100 // Larger size for single badge
        } else if newBadges.count <= 4 {
            return 80 // Medium size for 2-4 badges
        } else {
            return 65 // Smaller size for 5+ badges
        }
    }
    
    // Badge grid view (extracted to use in both scrolling and non-scrolling contexts)
    private var badgeGridContent: some View {
        LazyVGrid(columns: columns, spacing: 15) {
            ForEach(newBadges) { badge in
                VStack(spacing: 5) {
                    BadgeCell(
                        badge: badge,
                        isEarned: true,
                        progress: 1.0,
                        size: badgeSize
                    )
                    .onTapGesture {
                        selectedBadge = badge
                    }
                    
                    Text(badge.name)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.horizontal)
    }
    
    var body: some View {
        VStack(spacing: newBadges.count == 1 ? 10 : 15) {
            // Header
            VStack(spacing: 4) {
                Text("🎉 Achievement Unlocked! 🎉")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                
                Text("You've earned \(newBadges.count) new badge\(newBadges.count == 1 ? "" : "s")")
                    .font(.headline)
            }
            .padding(.bottom, newBadges.count == 1 ? 5 : 10)
            
            // Badge grid - conditionally use ScrollView
            Group {
                if newBadges.count > 6 {
                    // Use ScrollView only for many badges
                    ScrollView {
                        badgeGridContent
                    }
                    .frame(maxHeight: 300) // Limit height for many badges
                } else {
                    // Direct grid for few badges (no ScrollView)
                    badgeGridContent
                }
            }
            
            // Buttons with adaptive spacing
            VStack(spacing: newBadges.count == 1 ? 5 : 10) {
                Button(action: {
                    // Navigate to badges screen
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showBadges = true
                    }
                }) {
                    Text("View All Badges")
                        .padding(.vertical, newBadges.count == 1 ? 8 : 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    isPresented = false
                }) {
                    Text("Continue")
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(newBadges.count == 1 ? 15 : 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.systemBackground))
                .shadow(radius: 10)
        )
        .padding()
        .frame(maxWidth: 500) // Ensure it doesn't get too wide on larger devices
        .fixedSize(horizontal: false, vertical: true) // Key change: auto-size height to content
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailView(
                badge: badge,
                isEarned: true,
                progress: 1.0,
                earnedDate: Date(),
                statesVisited: badge.requiredStates,
                statesNeeded: []
            )
        }
    }
}