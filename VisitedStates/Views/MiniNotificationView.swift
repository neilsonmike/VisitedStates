import SwiftUI

/// A compact notification that appears as a tooltip from the badge button
struct MiniNotificationView: View {
    let badges: [AchievementBadge]
    @Binding var isPresented: Bool
    let onViewDetails: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with small icons
            HStack(spacing: 0) {
                ZStack {
                    ForEach(badges.prefix(3).indices, id: \.self) { index in
                        BadgeCell(
                            badge: badges[index],
                            isEarned: true,
                            progress: 1.0,
                            size: 30
                        )
                        .offset(x: CGFloat(index * 12), y: 0)
                        .zIndex(Double(badges.count - index))
                    }
                }
                .frame(width: badges.count > 1 ? 60 : 30, height: 30)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .padding(6)
                        .foregroundColor(.secondary)
                }
            }
            
            // Message
            VStack(alignment: .leading, spacing: 3) {
                Text("New Badge\(badges.count > 1 ? "s" : "") Earned!")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(badges.count == 1 ? badges[0].name : "\(badges.count) New Achievements")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // View button
            Button(action: {
                withAnimation {
                    isPresented = false
                }
                onViewDetails()
            }) {
                Text("View")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.top, 3)
        }
        .padding(10)
        .background(
            ZStack {
                // Main bubble background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
                
                // Tooltip triangle pointing to the badge button (right side, middle)
                GeometryReader { geo in
                    Path { path in
                        let width = geo.size.width
                        let height = geo.size.height
                        
                        // Draw triangle at the right side, middle
                        let triangleSize: CGFloat = 10
                        let triangleX = width
                        let triangleY = height / 2
                        
                        path.move(to: CGPoint(x: triangleX, y: triangleY - triangleSize))
                        path.addLine(to: CGPoint(x: triangleX + triangleSize, y: triangleY))
                        path.addLine(to: CGPoint(x: triangleX, y: triangleY + triangleSize))
                        path.closeSubpath()
                    }
                    .fill(Color(UIColor.systemBackground))
                    
                    // Shadow patch for the triangle
                    Path { path in
                        let width = geo.size.width
                        let height = geo.size.height
                        
                        let triangleSize: CGFloat = 10.5 // Slightly larger to create shadow effect
                        let triangleX = width
                        let triangleY = height / 2
                        
                        path.move(to: CGPoint(x: triangleX, y: triangleY - triangleSize))
                        path.addLine(to: CGPoint(x: triangleX + triangleSize, y: triangleY))
                        path.addLine(to: CGPoint(x: triangleX, y: triangleY + triangleSize))
                        path.closeSubpath()
                    }
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                }
            }
        )
        .frame(width: 180)
    }
}

struct MiniNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        // Sample with one badge
        ZStack {
            Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    // Position where the badge button would be
                    VStack {
                        MiniNotificationView(
                            badges: [AchievementBadgeProvider.allBadges[0]],
                            isPresented: .constant(true),
                            onViewDetails: {}
                        )
                        .offset(x: -120, y: 0)
                        
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 40, height: 40)
                    }
                    .padding()
                }
            }
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .frame(height: 300)
        
        // Sample with multiple badges
        ZStack {
            Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    VStack {
                        MiniNotificationView(
                            badges: Array(AchievementBadgeProvider.allBadges.prefix(3)),
                            isPresented: .constant(true),
                            onViewDetails: {}
                        )
                        .offset(x: -120, y: 0)
                        
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 40, height: 40)
                    }
                    .padding()
                }
            }
        }
        .previewLayout(.sizeThatFits)
        .frame(height: 300)
        .preferredColorScheme(.dark)
    }
}