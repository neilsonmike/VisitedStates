import SwiftUI
import MapKit

struct IntroMapView: View {
    @State private var showStates: [String] = []
    @State private var fadeOutIntro = false
    @State private var navigateToMain = false
    @State private var fadeIn = false

    @EnvironmentObject var settings: AppSettings

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

            Text("VisitedStates")
                .font(.custom("DoHyeon-Regular", size: 48))
                .foregroundColor(.red)
                .opacity(fadeOutIntro ? 0 : 1)
                .animation(.easeOut(duration: 1.5), value: fadeOutIntro)

        }
        .opacity(fadeIn ? 1 : 0)
        .animation(.easeIn(duration: 0.6), value: fadeIn)
        .onAppear {
            fadeIn = true
            showStates = []
            fadeOutIntro = false
            navigateToMain = false

            startAnimation()
        }
        .fullScreenCover(isPresented: $navigateToMain) {
            ContentView().environmentObject(settings).environmentObject(LocationManager.shared)
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
        
        // Delay before fading out the intro text
        DispatchQueue.main.asyncAfter(deadline: .now() + (stateFadeInterval * Double(stateSequence.count)) + fadeOutDelay) {
            withAnimation { fadeOutIntro = true }
        }
        
        // Delay before navigating to the main view
        DispatchQueue.main.asyncAfter(deadline: .now() + (stateFadeInterval * Double(stateSequence.count)) + navigateDelay) {
            navigateToMain = true
        }
    }

    private func drawState(context: inout GraphicsContext, stateName: String, size: CGSize) {
        guard let polygons = StateBoundaryManager.shared.statePolygons[stateName] else { return }

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

            context.fill(path, with: .color(.gray))
            context.stroke(path, with: .color(settings.stateStrokeColor), lineWidth: MapView.borderLineWidth)
        }
    }
    
    private func computeBoundingBox(for states: [String]) -> MKMapRect {
        var boundingBox: MKMapRect?
        for state in states {
            if let polygons = StateBoundaryManager.shared.statePolygons[state] {
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
