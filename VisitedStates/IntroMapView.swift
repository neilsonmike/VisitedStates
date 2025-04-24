import SwiftUI
import MapKit
import Combine

struct IntroMapView: View {
    @State private var showStates: [String] = []
    @State private var fadeOutIntro = false
    @State private var navigateToMain = false
    @State private var fadeIn = false
    
    // Access the app dependencies
    @EnvironmentObject var dependencies: AppDependencies
    
    private let stateSequence: [String] = [
        "Pennsylvania", "New York", "Ohio", "West Virginia",
        "Maryland", "Virginia", "Kentucky", "Tennessee",
        "North Carolina", "South Carolina", "Georgia", "Indiana",
    ]
    
    private let stateFadeInterval: TimeInterval = 0.15
    private let fadeOutDelay: TimeInterval = 0.3
    private let navigateDelay: TimeInterval = 0

    var body: some View {
        ZStack {
            // Background - change to use Color.primary.colorInvert() which respects dark mode
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            // State animations
            GeometryReader { geometry in
                Canvas { context, size in
                    for state in showStates {
                        drawState(context: &context, stateName: state, size: size)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(0.3)
            }
            .edgesIgnoringSafeArea(.all)

            // Logo image - explicitly centered
            VStack {
                Spacer()
                
                // Debugging - add a colored background to see if the image area is visible
                Image("VisitedStatesLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: UIScreen.main.bounds.width * 0.7) // 70% of screen width
                    .background(Color.clear) // For debugging - change to a color if needed
                    .opacity(fadeOutIntro ? 0 : 1)
                
                Spacer()
            }
            .animation(.easeOut(duration: 1.5), value: fadeOutIntro)
        }
        .opacity(fadeIn ? 1 : 0)
        .animation(.easeIn(duration: 0.6), value: fadeIn)
        .onAppear {
            // Debug log to ensure this view is loaded
            print("IntroMapView appeared - animation will start")
            
            fadeIn = true
            showStates = []
            fadeOutIntro = false
            navigateToMain = false

            startAnimation()
        }
        .fullScreenCover(isPresented: $navigateToMain) {
            ContentView()
                .environmentObject(dependencies)
        }
    }

    private func startAnimation() {
        // Animate the appearance of each state in sequence
        for (index, state) in stateSequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (stateFadeInterval * Double(index))) {
                withAnimation {
                    showStates.append(state)
                }
            }
        }
        
        // Delay before fading out the intro text/logo
        DispatchQueue.main.asyncAfter(deadline: .now() + (stateFadeInterval * Double(stateSequence.count)) + fadeOutDelay) {
            // Debug log to ensure this is triggered
            print("Fading out intro logo")
            withAnimation { fadeOutIntro = true }
        }
        
        // Delay before navigating to the main view
        DispatchQueue.main.asyncAfter(deadline: .now() + (stateFadeInterval * Double(stateSequence.count)) + navigateDelay) {
            // Debug log to ensure this is triggered
            print("Navigating to main view")
            navigateToMain = true
        }
    }

    private func drawState(context: inout GraphicsContext, stateName: String, size: CGSize) {
        // Access the boundary service to get state polygons
        guard let polygons = dependencies.stateBoundaryService.statePolygons[stateName] else { return }

        let boundingBox = computeBoundingBox(for: stateSequence)

        let scaleX = size.width / CGFloat(boundingBox.size.width)
        let scaleY = size.height / CGFloat(boundingBox.size.height)
        let scale = min(scaleX, scaleY)

        let offsetX = (size.width - CGFloat(boundingBox.size.width) * scale) / 2
        let offsetY = (size.height - CGFloat(boundingBox.size.height) * scale) / 2

        func transform(_ point: MKMapPoint) -> CGPoint {
            return CGPoint(
                x: offsetX + CGFloat(point.x - boundingBox.origin.x) * scale,
                y: offsetY + CGFloat(point.y - boundingBox.origin.y) * scale
            )
        }

        // Use gray for the intro animation, but adapt to dark mode
        let fillColor = Color.gray
        let strokeColor = Color(UIColor.systemBackground) // This will be white in light mode and black in dark mode

        for polygon in polygons {
            var path = Path()
            let count = polygon.pointCount
            guard count > 0 else { continue }
            let points = polygon.points()
            let firstPoint = transform(points[0])

            path.move(to: firstPoint)
            for i in 1..<count {
                let point = transform(points[i])
                path.addLine(to: point)
            }
            path.closeSubpath()

            context.fill(path, with: .color(fillColor))
            context.stroke(path, with: .color(strokeColor), lineWidth: 0.5)
        }
    }
    
    private func computeBoundingBox(for states: [String]) -> MKMapRect {
        var boundingBox: MKMapRect?
        for state in states {
            if let polygons = dependencies.stateBoundaryService.statePolygons[state] {
                for polygon in polygons {
                    if boundingBox == nil {
                        boundingBox = polygon.boundingMapRect
                    } else {
                        boundingBox = boundingBox?.union(polygon.boundingMapRect)
                    }
                }
            }
        }
        return boundingBox ?? MKMapRect()
    }
}
