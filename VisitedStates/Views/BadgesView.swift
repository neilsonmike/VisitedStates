import SwiftUI

/// The main view for displaying badges and progress
struct BadgesView: View {
    @State private var filterMode: BadgeFilterMode = .all
    @State private var selectedBadge: AchievementBadge? = nil
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var dependencies: AppDependencies

    // All available badges
    let allBadges = AchievementBadgeProvider.allBadges

    // Badge service for tracking and progress
    private let badgeService = BadgeTrackingService()
    @State private var newBadgeIds: [String] = []
    
    enum BadgeFilterMode: String, CaseIterable {
        case all = "All"
        case earned = "Earned"
        case unearned = "Unearned"
        
        var sfSymbol: String {
            switch self {
            case .all: return "circle.grid.3x3.fill"
            case .earned: return "checkmark.circle.fill"
            case .unearned: return "circle"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Fixed title area - always visible
                VStack(spacing: 0) {
                    // Title "Badges" is shown by navigationTitle
                    
                    // Filter tabs - always visible
                    Picker("Filter", selection: $filterMode) {
                        ForEach(BadgeFilterMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.sfSymbol)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(
                        Color(UIColor.systemBackground)
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
                    )
                    .zIndex(1) // Ensure it stays on top
                    
                    // Add divider at the bottom of the fixed section for visual separation
                    Divider()
                        .background(Color.gray.opacity(0.3))
                        .padding(.horizontal, 0)
                }
                
                // Scrollable content with stats header
                ScrollView {
                    VStack(spacing: 0) {
                        // Stats section that will scroll away
                        BadgeStatsHeader(
                            totalEarned: earnedBadges.count,
                            totalBadges: allBadges.count
                        )
                        .padding(.horizontal)
                        .padding(.top, 5)
                        .padding(.bottom, 10)
                        
                        // Explanatory text about GPS detection
                        Text("Note: Badges are only awarded for GPS-detected locations, not manually edited states.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 25)
                            .padding(.bottom, 10)
                        
                        // Badge grid
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 80))],
                            alignment: .center,
                            spacing: 12
                        ) {
                            ForEach(filteredBadges) { badge in
                                BadgeTile(
                                    badge: badge,
                                    isEarned: isEarned(badge),
                                    progress: progressFor(badge),
                                    isNew: newBadgeIds.contains(badge.id)
                                )
                                .onTapGesture {
                                    // Just set the selected badge, sheet will open automatically
                                    selectedBadge = badge
                                }
                            }
                        }
                        .padding()
                    }
                }
                .sheet(item: $selectedBadge) { badge in
                    BadgeDetailView(
                        badge: badge,
                        isEarned: isEarned(badge),
                        progress: progressFor(badge),
                        earnedDate: earnedDateFor(badge),
                        statesVisited: visitedStatesFor(badge),
                        statesNeeded: neededStatesFor(badge)
                    )
                }
            }
            .navigationTitle("Badges")
            // Using the more modern toolbar API for consistency
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                // Load any new badges to highlight
                self.newBadgeIds = badgeService.getNewBadges()

                // Post notification that badges screen was viewed
                NotificationCenter.default.post(name: NSNotification.Name("BadgesViewed"), object: nil)

                // If there are new badges being viewed, mark them as no longer new after 5 seconds
                if !newBadgeIds.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        badgeService.clearNewBadges()
                    }
                }
            }
        }
    }
    
    /// A single badge tile in the grid
    struct BadgeTile: View {
        let badge: AchievementBadge
        let isEarned: Bool
        let progress: Float
        let isNew: Bool

        init(badge: AchievementBadge, isEarned: Bool, progress: Float, isNew: Bool = false) {
            self.badge = badge
            self.isEarned = isEarned
            self.progress = progress
            self.isNew = isNew
        }

        var body: some View {
            VStack {
                ZStack {
                    BadgeCell(
                        badge: badge,
                        isEarned: isEarned,
                        progress: progress
                    )

                    if isNew {
                        Text("NEW")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .offset(x: 0, y: -28)
                    }
                }

                Text(badge.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 30)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsTightening(false)
                    .minimumScaleFactor(0.8)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isNew ? Color.yellow.opacity(0.1) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isNew ? Color.yellow.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /// Filters badges based on current filter settings
    var filteredBadges: [AchievementBadge] {
        let badges = allBadges
        
        // Apply earned/unearned filter
        switch filterMode {
        case .all:
            return badges
        case .earned:
            return badges.filter { isEarned($0) }
        case .unearned:
            return badges.filter { !isEarned($0) }
        }
    }
    
    /// Returns earned badges
    var earnedBadges: [AchievementBadge] {
        allBadges.filter { isEarned($0) }
    }
    
    // MARK: - Real Badge Data Methods

    /// Check if a badge is earned
    func isEarned(_ badge: AchievementBadge) -> Bool {
        let earnedBadges = badgeService.getEarnedBadges()
        return earnedBadges[badge.id] != nil
    }

    /// Get progress for a badge
    func progressFor(_ badge: AchievementBadge) -> Float {
        // Use visited states from settings service
        let visitedStates = dependencies.settingsService.getActiveGPSVerifiedStates().map { $0.stateName }
        return badgeService.calculateBadgeProgress(badge, visitedStates: visitedStates)
    }

    /// Get earned date for a badge
    func earnedDateFor(_ badge: AchievementBadge) -> Date? {
        let earnedBadges = badgeService.getEarnedBadges()
        return earnedBadges[badge.id]
    }

    /// Get states visited for a badge
    func visitedStatesFor(_ badge: AchievementBadge) -> [String] {
        // Use visited states from settings service
        let visitedStates = dependencies.settingsService.getActiveGPSVerifiedStates().map { $0.stateName }
        return badgeService.getVisitedStatesForBadge(badge, visitedStates: visitedStates)
    }

    /// Get states needed for a badge
    func neededStatesFor(_ badge: AchievementBadge) -> [String] {
        // If badge is earned, return empty array (no states needed)
        if isEarned(badge) {
            return []
        }

        // Use visited states from settings service
        let visitedStates = dependencies.settingsService.getActiveGPSVerifiedStates().map { $0.stateName }
        return badgeService.getNeededStatesForBadge(badge, visitedStates: visitedStates)
    }
}

/// Header view showing badge statistics
struct BadgeStatsHeader: View {
    let totalEarned: Int
    let totalBadges: Int
    
    private var percentComplete: Int {
        guard totalBadges > 0 else { return 0 }
        return Int((Double(totalEarned) / Double(totalBadges)) * 100)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 30) {
                // Earned badges stat
                VStack {
                    Text("\(totalEarned)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Earned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Badge progress bar
                VStack {
                    Text("\(percentComplete)%")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Total badges stat
                VStack {
                    Text("\(totalBadges)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress bar
            ProgressView(value: Double(totalEarned), total: Double(totalBadges))
                .progressViewStyle(LinearProgressViewStyle(tint: Color.green))
                .padding(.horizontal, 10)
        }
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

/// Preview provider for BadgesView
struct BadgesView_Previews: PreviewProvider {
    static var previews: some View {
        BadgesView()
            .environmentObject(AppDependencies.mock())
    }
}