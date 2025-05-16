import SwiftUI

/// Detailed view of a badge showing progress and requirements
struct BadgeDetailView: View {
    let badge: AchievementBadge
    let isEarned: Bool
    let progress: Float
    let earnedDate: Date?
    let statesVisited: [String]
    let statesNeeded: [String]

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Helper method to get milestone target count outside of View body
    private func getMilestoneTargetCount(badgeId: String) -> Int {
        switch badgeId {
        case "explorer": return 10
        case "journeyer": return 20
        case "voyager": return 30
        case "adventurer": return 40
        case "completionist": return 50
        default: return 1
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Badge header with category
                Text(badge.category.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)

                // Larger badge with progress
                BadgeCell(
                    badge: badge,
                    isEarned: isEarned,
                    progress: progress,
                    size: 140
                )

                Text(badge.name)
                    .font(.title)
                    .bold()

                Text(badge.description)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Earned badge information
                if isEarned, let date = earnedDate {
                    HStack {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundColor(.green)
                        Text("Earned on \(dateFormatter.string(from: date))")
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green.opacity(0.1))
                    )

                    // Celebration message
                    Text("Congratulations on earning this badge!")
                        .font(.subheadline)
                        .padding(.top, 5)
                } else if !statesNeeded.isEmpty {
                    // Progress display bar for unearned badges
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.green))
                        .padding(.horizontal, 30)

                    Text("\(Int(progress * 100))% complete")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Milestone badges: Show progress text instead of state lists
                if badge.category == .milestone && badge.requiredStates.first == "Any" {
                    VStack(spacing: 16) {
                        if isEarned {
                            Text("You've visited enough states to earn this badge!")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.green)
                                .padding()
                        } else {
                            // Get milestone target count
                            let targetCount = getMilestoneTargetCount(badgeId: badge.id)

                            Text("Visit \(targetCount) states to earn this badge")
                                .multilineTextAlignment(.center)
                                .padding()

                            // Assume progress is based on visitedCount/targetCount
                            Text("Current progress: \(Int(progress * 100))%")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                // Special condition badges: Show special message
                else if badge.specialCondition != nil {
                    VStack(spacing: 16) {
                        if isEarned {
                            Text("You've completed this special achievement!")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.green)
                                .padding()
                        } else {
                            Text("Complete the special requirement to earn this badge")
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                // Standard badges with specific states: Show state lists
                else {
                    VStack(alignment: .leading, spacing: 20) {
                        if !statesVisited.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("States visited (\(statesVisited.count)):")
                                    .font(.headline)
                                    .padding(.bottom, 4)

                                ForEach(statesVisited.sorted(), id: \.self) { state in
                                    StateCompletionItem(
                                        stateName: state,
                                        isCompleted: true
                                    )
                                    .padding(.bottom, 4)
                                }
                            }
                            .padding(.horizontal, 5)
                        }

                        if !statesNeeded.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("States needed (\(statesNeeded.count)):")
                                    .font(.headline)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)

                                ForEach(statesNeeded.sorted(), id: \.self) { state in
                                    StateCompletionItem(
                                        stateName: state,
                                        isCompleted: false
                                    )
                                    .padding(.bottom, 4)
                                }
                            }
                            .padding(.horizontal, 5)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                // Special note for special condition badges
                if badge.specialCondition != nil {
                    specialConditionNote
                        .padding()
                }

                Spacer()
            }
        }
        .navigationTitle("Badge Details")
    }

    /// Shows a note about special requirements for certain badges
    private var specialConditionNote: some View {
        VStack(alignment: .leading) {
            Text("Special Requirements")
                .font(.headline)

            switch badge.specialCondition {
            case .multipleStatesInOneDay(let count):
                Text("Visit \(count) different states in a single calendar day.")
            case .uniqueStatesInDays(let count, let days):
                Text("Visit \(count) unique states within a \(days)-day span.")
            case .sameCalendarYear(let count):
                Text("Visit \(count) different states within the same calendar year.")
            case .returningVisit(let state, let days):
                Text("Return to \(state) after at least \(days) days since your last visit.")
            case .directionStates(let direction):
                Text("Visit all states with '\(direction)' in their name.")
            case .none:
                Text("This badge has special requirements beyond just visiting specific states.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.1))
        )
    }
}

/// Helper view for showing state completion status
struct StateCompletionItem: View {
    let stateName: String
    let isCompleted: Bool

    var body: some View {
        HStack {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .gray)
                .frame(width: 20)

            Text(stateName)
                .font(.subheadline)
                .foregroundColor(isCompleted ? .primary : .secondary)

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCompleted ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCompleted ? Color.green.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Preview provider for BadgeDetailView
struct BadgeDetailView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Earned badge
            BadgeDetailView(
                badge: AchievementBadgeProvider.allBadges[0],
                isEarned: true,
                progress: 1.0,
                earnedDate: Date().addingTimeInterval(-86400 * 30),
                statesVisited: ["California"],
                statesNeeded: []
            )

            // In progress badge
            BadgeDetailView(
                badge: AchievementBadgeProvider.allBadges[7],
                isEarned: false,
                progress: 0.3,
                earnedDate: nil,
                statesVisited: ["Connecticut", "Delaware", "Florida", "Georgia"],
                statesNeeded: ["Maine", "Maryland", "Massachusetts", "New Hampshire",
                               "New Jersey", "New York", "North Carolina",
                               "Rhode Island", "South Carolina", "Virginia"]
            )

            // Special condition badge
            BadgeDetailView(
                badge: AchievementBadgeProvider.allBadges[10],
                isEarned: false,
                progress: 0.0,
                earnedDate: nil,
                statesVisited: [],
                statesNeeded: ["Visit 3 states in one day"]
            )
        }
    }
}