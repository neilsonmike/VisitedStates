import SwiftUI

// Define a simple badge view for notifications without checkmark
private struct SimpleBadgeView: View {
    let badge: AchievementBadge
    let size: CGFloat

    var body: some View {
        ZStack {
            // Outer white ring
            Circle()
                .fill(Color.white)
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 1, y: 1)

            // Inner colored circle
            Circle()
                .fill(badge.color)
                .frame(width: size * 0.85, height: size * 0.85)

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
        }
        .padding(2)
    }
}

/// A combined notification for state detection and badge earning
struct StateNotificationView: View {
    // Core properties
    private let stateName: String
    private let badges: [AchievementBadge]
    private let factoid: String?
    @Binding private var isPresented: Bool
    private let onViewBadges: () -> Void

    // Additional properties for extended functionality
    private let skipWelcome: Bool
    private let totalBadgeCount: Int?

    // Primary initializer with all parameters
    init(
        stateName: String,
        badges: [AchievementBadge],
        factoid: String?,
        isPresented: Binding<Bool>,
        skipWelcome: Bool = false,
        totalBadgeCount: Int? = nil,
        onViewBadges: @escaping () -> Void
    ) {
        self.stateName = stateName
        self.badges = badges
        self.factoid = factoid
        self._isPresented = isPresented
        self.skipWelcome = skipWelcome
        self.totalBadgeCount = totalBadgeCount
        self.onViewBadges = onViewBadges
    }

    private var hasBadges: Bool {
        return !badges.isEmpty
    }

    private var shouldShowWelcomeSection: Bool {
        return !skipWelcome
    }

    private var effectiveBadgeCount: Int {
        return totalBadgeCount ?? badges.count
    }

    private var hasAdditionalBadges: Bool {
        if let total = totalBadgeCount {
            return total > badges.count
        }
        return false
    }

    var body: some View {
        VStack(spacing: 10) {
            // State notification - only show if not skipped
            if shouldShowWelcomeSection {
                VStack(alignment: .leading, spacing: 4) {
                    // Header with state name
                    HStack {
                        // Use our custom notification icon
                        Image("NotificationIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30) // 50% larger for better visibility
                            .clipShape(Circle()) // Clip to circular shape for consistent look
                            .padding(2) // Add a small padding around the icon

                        Text("Welcome to \(stateName)!")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()

                        // Always show close button in top right
                        Button(action: {
                            withAnimation {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12))
                                .padding(6)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Factoid if available
                    Group {
                        if let factoid = factoid, !factoid.isEmpty {
                            Text(factoid)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true) // Allow dynamic height
                                .padding(.top, 2)
                        } else {
                            // Empty view when no factoid
                            EmptyView()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Badge earned section (if any)
            if hasBadges {
                // Only show divider if we're showing both sections
                if shouldShowWelcomeSection {
                    Divider()
                }

                VStack(alignment: .leading, spacing: 6) {
                    // Badge header
                    HStack {
                        // Badge title
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)

                            Text("New Badge\(effectiveBadgeCount > 1 ? "s" : "") Earned!")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        // View button in the header row
                        Button(action: {
                            withAnimation {
                                isPresented = false
                            }
                            onViewBadges()
                        }) {
                            Text("View")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }

                        // Always show close button, even in badge-only mode
                        if !shouldShowWelcomeSection {
                            Button(action: {
                                withAnimation {
                                    isPresented = false
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12))
                                    .padding(6)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Badge icons - stacked vertically for better visibility
                    HStack(spacing: 5) {
                        // Vertical stack of badges
                        VStack(alignment: .leading, spacing: 4) {
                            // Show up to 2 badges individually (or 3 if only 3 total)
                            let displayCount = min(effectiveBadgeCount <= 3 ? 3 : 2, badges.count)

                            ForEach(0..<displayCount, id: \.self) { index in
                                HStack(spacing: 8) {
                                    // Use our custom SimpleBadgeView without checkmark
                                    SimpleBadgeView(
                                        badge: badges[index],
                                        size: 24
                                    )

                                    Text(badges[index].name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            // "And X more" text if needed
                            if effectiveBadgeCount > 3 {
                                HStack(spacing: 8) {
                                    // Use consistent styling for the "more" indicator
                                    ZStack {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 24, height: 24)

                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                    }

                                    Text("And \(effectiveBadgeCount - displayCount) more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color(white: 0, opacity: 0.15), radius: 5, x: 0, y: 2)
                // Add a subtle colored border to match app branding
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .onAppear {
            // Auto-dismiss after 7 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                withAnimation {
                    isPresented = false
                }
            }
        }
    }
}


struct StateNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // Preview with factoid, no badges
            StateNotificationView(
                stateName: "California",
                badges: [],
                factoid: "Home to Hollywood and Silicon Valley, California has the largest economy of any U.S. state.",
                isPresented: .constant(true),
                skipWelcome: false,
                totalBadgeCount: nil,
                onViewBadges: {}
            )
            .padding()

            // Preview with one badge
            StateNotificationView(
                stateName: "Colorado",
                badges: [AchievementBadgeProvider.allBadges[0]],
                factoid: "Colorado contains 75% of the land area of the U.S. with an altitude over 10,000 feet.",
                isPresented: .constant(true),
                skipWelcome: false,
                totalBadgeCount: nil,
                onViewBadges: {}
            )
            .padding()

            // Preview with multiple badges
            StateNotificationView(
                stateName: "New York",
                badges: Array(AchievementBadgeProvider.allBadges.prefix(3)),
                factoid: nil,
                isPresented: .constant(true),
                skipWelcome: false,
                totalBadgeCount: nil,
                onViewBadges: {}
            )
            .padding()

            // Preview with skipped welcome
            StateNotificationView(
                stateName: "Florida",
                badges: Array(AchievementBadgeProvider.allBadges.prefix(2)),
                factoid: nil,
                isPresented: .constant(true),
                skipWelcome: true,
                totalBadgeCount: nil,
                onViewBadges: {}
            )
            .padding()

            // Preview with "and more" badges
            StateNotificationView(
                stateName: "Texas",
                badges: Array(AchievementBadgeProvider.allBadges.prefix(3)),
                factoid: "Texas is the second largest state in both area and population.",
                isPresented: .constant(true),
                skipWelcome: false,
                totalBadgeCount: 5,
                onViewBadges: {}
            )
            .padding()
        }
        .preferredColorScheme(.dark)
        .background(Color(white: 0.5, opacity: 0.3))
        .previewLayout(.sizeThatFits)
    }
}