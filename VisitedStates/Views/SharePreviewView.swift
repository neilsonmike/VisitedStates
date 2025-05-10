import SwiftUI
import MapKit
import Combine

struct SharePreviewView: View {
    // Access app dependencies
    @EnvironmentObject var dependencies: AppDependencies
    
    // Local state
    @State private var visitedStates: [String] = []
    @State private var stateFillColor: Color = .red
    @State private var stateStrokeColor: Color = .white
    @State private var backgroundColor: Color = .white
    @State private var cancellables = Set<AnyCancellable>()
    
    // Constants - same as MapView
    static let borderLineWidth: CGFloat = 0.5
    static let californiaCenter = CLLocationCoordinate2D(latitude: 37.3, longitude: -119.5)
    static let californiaSpan = MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0)
    
    static let referenceScale: CGFloat = {
        let refRect = regionToMapRect(center: californiaCenter, span: californiaSpan)
        let extraPaddingFraction: Double = 0.02
        let extraDx = refRect.size.width * extraPaddingFraction
        let extraDy = refRect.size.height * extraPaddingFraction
        let paddedRect = refRect.insetBy(dx: -extraDx, dy: -extraDy)
        
        let testWidth: CGFloat = 400
        let testHeight: CGFloat = 400
        let scaleX = testWidth / CGFloat(paddedRect.size.width)
        let scaleY = testHeight / CGFloat(paddedRect.size.height)
        return min(scaleX, scaleY)
    }()
    
    // Preferred map rectangles for special state handling
    static let preferredMapRects: [String: MKMapRect] = {
        let alaskaRect = regionToMapRect(
            center: CLLocationCoordinate2D(latitude: 64.0, longitude: -152.0),
            span: MKCoordinateSpan(latitudeDelta: 275.0, longitudeDelta: 275.0)
        )
        let hawaiiRect = regionToMapRect(
            center: CLLocationCoordinate2D(latitude: 20.7, longitude: -156.5),
            span: MKCoordinateSpan(latitudeDelta: 4.0, longitudeDelta: 30.0)
        )
        
        return [
            "Alaska": alaskaRect,
            "Hawaii": hawaiiRect
        ]
    }()
    
    static func regionToMapRect(center: CLLocationCoordinate2D, span: MKCoordinateSpan) -> MKMapRect {
        let centerPoint = MKMapPoint(center)
        let widthMeters = span.longitudeDelta * 111_000.0
        let heightMeters = span.latitudeDelta * 111_000.0
        let origin = MKMapPoint(x: centerPoint.x - widthMeters / 2,
                                y: centerPoint.y - heightMeters / 2)
        return MKMapRect(origin: origin,
                        size: MKMapSize(width: widthMeters, height: heightMeters))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - use explicit solid background
                backgroundColor
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Add logo at the top with some padding
                    Image("VisitedStatesLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.8) // 80% of width
                        .padding(.top, geometry.size.height * 0.04) // 4% top padding
                    
                    // Exclude D.C. from count for share stats
                    let visitedStatesExcludingDC = visitedStates.filter { $0 != "District of Columbia" }
                    let visitedCount = visitedStatesExcludingDC.count
                    
                    // Count label
                    let labelText = "\(visitedCount)/50 States Visited"
                    Text(labelText)
                        .foregroundColor(.gray)
                        .font(.custom("DoHyeon-Regular", size: 48))
                        .padding(.bottom, geometry.size.height * 0.02) // 2% bottom padding
                    
                    // Map area - takes remaining space
                    ZStack {
                        let showAlaska = visitedStates.contains("Alaska")
                        let showHawaii = visitedStates.contains("Hawaii")
                        
                        // For drawing, use all visitedStates (so D.C. is drawn if visited)
                        let contiguousStates = visitedStates.filter { $0 != "Alaska" && $0 != "Hawaii" }
                        let noContiguousStates = contiguousStates.isEmpty
                        
                        // Special case 1: Only Alaska and Hawaii, nothing else
                        if visitedCount == 2 && showAlaska && showHawaii && noContiguousStates {
                            VStack(spacing: 0) {
                                // Alaska in top position - smaller to avoid overlap with logo
                                ShareInsetStateView(stateName: "Alaska")
                                    .environmentObject(dependencies)
                                    .frame(width: 600, height: 600)
                                    
                                
                                // Hawaii in bottom position - smaller than Alaska
                                ShareInsetStateView(stateName: "Hawaii")
                                    .environmentObject(dependencies)
                                    .frame(width: 600, height: 600)
                                   
                            }
                            .padding(.top, geometry.size.height * 0.05) // Push down to avoid logo
                        }
                        // Special case 2: Only Alaska or only Hawaii
                        else if visitedCount == 1 && (showAlaska || showHawaii) && noContiguousStates {
                            if showAlaska {
                                // Alaska centered in the main map area
                                ShareFullScreenStateView(state: "Alaska")
                                    .environmentObject(dependencies)
                                    .frame(width: geometry.size.width, height: geometry.size.height * 0.6)
                            } else {
                                // Hawaii centered in the main map area
                                ShareFullScreenStateView(state: "Hawaii")
                                    .environmentObject(dependencies)
                                    .frame(width: geometry.size.width, height: geometry.size.height * 0.6)
                            }
                        }
                        // Regular case: Show contiguous states only (no AK/HI)
                        else if !showAlaska && !showHawaii {
                            ZStack(alignment: .bottomLeading) {
                                // Main map of contiguous states only
                                ShareContiguousStatesCanvas(visitedStates: contiguousStates)
                                    .environmentObject(dependencies)
                                    .frame(width: geometry.size.width * 0.95, height: geometry.size.height * 0.75)
                                    .position(x: 600, y: 600)
                            }
                        }
                        // Mixed case: Show contiguous states with Alaska/Hawaii insets
                        else {
                            ZStack(alignment: .bottomLeading) {
                                // Main map of contiguous states - top 75% of map area
                                ShareContiguousStatesCanvas(visitedStates: contiguousStates)
                                    .environmentObject(dependencies)
                                    .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.55)
                                    .position(x: 600, y: 420)

                                
                                // Insets for Alaska and Hawaii - bottom 25% of map area
                                if showAlaska && showHawaii {
                                    // Explicit positioning for Alaska and Hawaii together
                                    ZStack {
                                        // Alaska - adjust xOffset and yOffset as needed
                                        let akXOffset: CGFloat = 250
                                        let akYOffset: CGFloat = 550
                                        
                                        ShareInsetStateView(stateName: "Alaska")
                                            .environmentObject(dependencies)
                                            .frame(width: geometry.size.width * 0.28, height: geometry.size.width * 0.28)
                                            .position(x: akXOffset, y: geometry.size.height - akYOffset)
                                        
                                        // Hawaii - adjust xOffset and yOffset as needed
                                        let hiXOffset: CGFloat = 625
                                        let hiYOffset: CGFloat = 550
                                        
                                        ShareInsetStateView(stateName: "Hawaii")
                                            .environmentObject(dependencies)
                                            .frame(width: geometry.size.width * 0.25, height: geometry.size.width * 0.25)
                                            .position(x: hiXOffset, y: geometry.size.height - hiYOffset)
                                    }
                                } else if showAlaska {
                                    // Just Alaska - adjust xOffset and yOffset as needed
                                    let akXOffset: CGFloat = 250
                                    let akYOffset: CGFloat = 550
                                    
                                    ShareInsetStateView(stateName: "Alaska")
                                        .environmentObject(dependencies)
                                        .frame(width: geometry.size.width * 0.28, height: geometry.size.width * 0.28)
                                        .position(x: akXOffset, y: geometry.size.height - akYOffset)
                                } else if showHawaii {
                                    // Just Hawaii - adjust xOffset and yOffset as needed
                                    let hiXOffset: CGFloat = 250
                                    let hiYOffset: CGFloat = 550
                                    
                                    ShareInsetStateView(stateName: "Hawaii")
                                        .environmentObject(dependencies)
                                        .frame(width: geometry.size.width * 0.28, height: geometry.size.width * 0.28)
                                        .position(x: hiXOffset, y: geometry.size.height - hiYOffset)
                                }
                            }
                        }
                    }
                    .frame(height: geometry.size.height * 0.6) // Allocate 60% of view height to map area
                    
                    Spacer() // Push everything up to make room for footer area
                }
            }
            // Make sure to use explicit solid background to ensure opaque image
            .background(backgroundColor)
        }
        .onAppear {
            setupSubscriptions()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }
    
    private func setupSubscriptions() {
        // Subscribe to visited states changes
        dependencies.settingsService.visitedStates
            .sink { states in
                self.visitedStates = states
            }
            .store(in: &cancellables)
        
        // Subscribe to color changes
        dependencies.settingsService.stateFillColor
            .sink { color in
                self.stateFillColor = color
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.stateStrokeColor
            .sink { color in
                self.stateStrokeColor = color
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.backgroundColor
            .sink { color in
                self.backgroundColor = color
            }
            .store(in: &cancellables)
    }
}

// MARK: - ShareContiguousStatesCanvas

struct ShareContiguousStatesCanvas: View {
    @EnvironmentObject var dependencies: AppDependencies
    let visitedStates: [String]
    
    // Local state from subscriptions
    @State private var fillColor: Color = .red
    @State private var strokeColor: Color = .white
    @State private var backgroundColor: Color = .white
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        Canvas { context, size in
            if !visitedStates.isEmpty,
               let unionRect = computeUnionMapRect(for: visitedStates) {
                
                let extraPaddingFraction: Double = 0.02
                let extraDx = unionRect.size.width * extraPaddingFraction
                let extraDy = unionRect.size.height * extraPaddingFraction
                let paddedUnionRect = unionRect.insetBy(dx: -extraDx, dy: -extraDy)
                
                let scaleX = size.width / CGFloat(paddedUnionRect.size.width)
                let scaleY = size.height / CGFloat(paddedUnionRect.size.height)
                let scale = min(scaleX, scaleY)
                
                let offsetX = (size.width - (paddedUnionRect.size.width * scale)) / 2
                let offsetY = (size.height - (paddedUnionRect.size.height * scale)) / 2
                
                for state in visitedStates {
                    if let polygons = dependencies.stateBoundaryService.statePolygons[state] {
                        for polygon in polygons {
                            var path = Path()
                            let pointCount = polygon.pointCount
                            guard pointCount > 0 else { continue }
                            let points = polygon.points()
                            let firstPoint = points[0]
                            
                            func transformedX(_ p: MKMapPoint) -> CGFloat {
                                offsetX + CGFloat(p.x - paddedUnionRect.origin.x) * scale
                            }
                            func transformedY(_ p: MKMapPoint) -> CGFloat {
                                offsetY + CGFloat(p.y - paddedUnionRect.origin.y) * scale
                            }
                            
                            path.move(to: CGPoint(x: transformedX(firstPoint), y: transformedY(firstPoint)))
                            for i in 1..<pointCount {
                                let mp = points[i]
                                path.addLine(to: CGPoint(x: transformedX(mp), y: transformedY(mp)))
                            }
                            path.closeSubpath()
                            
                            context.fill(path, with: .color(fillColor))
                            context.stroke(path, with: .color(strokeColor), lineWidth: SharePreviewView.borderLineWidth)
                        }
                    }
                }
            }
        }
        .onAppear {
            setupSubscriptions()
        }
        .onDisappear {
            cancellables.removeAll()
        }
        // Use explicit background to ensure opacity
        .background(backgroundColor)
    }
    
    private func setupSubscriptions() {
        // IMPORTANT FIX: Get current values first
        fillColor = dependencies.settingsService.stateFillColor.value
        strokeColor = dependencies.settingsService.stateStrokeColor.value
        backgroundColor = dependencies.settingsService.backgroundColor.value
        
        // Then subscribe to future changes
        dependencies.settingsService.stateFillColor
            .sink { color in
                self.fillColor = color
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.stateStrokeColor
            .sink { color in
                self.strokeColor = color
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.backgroundColor
            .sink { color in
                self.backgroundColor = color
            }
            .store(in: &cancellables)
    }
    
    func computeUnionMapRect(for states: [String]) -> MKMapRect? {
        var unionRect: MKMapRect?
        for state in states {
            if let polys = dependencies.stateBoundaryService.statePolygons[state] {
                for poly in polys {
                    unionRect = unionRect?.union(poly.boundingMapRect) ?? poly.boundingMapRect
                }
            }
        }
        return unionRect
    }
}

// MARK: - ShareFullScreenStateView

struct ShareFullScreenStateView: View {
    var state: String
    @EnvironmentObject var dependencies: AppDependencies
    
    // Local state
    @State private var fillColor: Color = .red
    @State private var strokeColor: Color = .white
    @State private var backgroundColor: Color = .white
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                if let mapRect = SharePreviewView.preferredMapRects[state] {
                    let extraPaddingFraction: Double = 0.02
                    let extraDx = mapRect.size.width * extraPaddingFraction
                    let extraDy = mapRect.size.height * extraPaddingFraction
                    let paddedRect = mapRect.insetBy(dx: -extraDx, dy: -extraDy)
                    
                    let scaleX = size.width / CGFloat(paddedRect.size.width)
                    let scaleY = size.height / CGFloat(paddedRect.size.height)
                    let scale = min(scaleX, scaleY)
                    
                    let offsetX = (size.width - (paddedRect.size.width * scale)) / 2
                    let offsetY = (size.height - (paddedRect.size.height * scale)) / 2
                    
                    func tx(_ p: MKMapPoint) -> CGFloat {
                        offsetX + CGFloat(p.x - paddedRect.origin.x) * scale
                    }
                    func ty(_ p: MKMapPoint) -> CGFloat {
                        offsetY + CGFloat(p.y - paddedRect.origin.y) * scale
                    }
                    
                    if let polygons = dependencies.stateBoundaryService.statePolygons[state] {
                        for polygon in polygons {
                            var path = Path()
                            let count = polygon.pointCount
                            guard count > 0 else { continue }
                            let pts = polygon.points()
                            let firstPt = pts[0]
                            
                            path.move(to: CGPoint(x: tx(firstPt), y: ty(firstPt)))
                            for i in 1..<count {
                                let mp = pts[i]
                                path.addLine(to: CGPoint(x: tx(mp), y: ty(mp)))
                            }
                            path.closeSubpath()
                            
                            context.fill(path, with: .color(fillColor))
                            context.stroke(path, with: .color(strokeColor), lineWidth: SharePreviewView.borderLineWidth)
                        }
                    }
                }
                else if let unionRect = computeUnionMapRectForState(state: state) {
                    let extraPaddingFraction: Double = 0.02
                    let extraDx = unionRect.size.width * extraPaddingFraction
                    let extraDy = unionRect.size.height * extraPaddingFraction
                    let paddedUnionRect = unionRect.insetBy(dx: -extraDx, dy: -extraDy)
                    
                    let scaleX = size.width / CGFloat(paddedUnionRect.size.width)
                    let scaleY = size.height / CGFloat(paddedUnionRect.size.height)
                    let scale = min(scaleX, scaleY)
                    
                    let drawnWidth  = CGFloat(paddedUnionRect.size.width) * scale
                    let drawnHeight = CGFloat(paddedUnionRect.size.height) * scale
                    
                    let offsetX = (size.width - drawnWidth) / 2
                    let offsetY = (size.height - drawnHeight) / 2
                    
                    func transformedX(_ p: MKMapPoint) -> CGFloat {
                        offsetX + CGFloat(p.x - paddedUnionRect.origin.x) * scale
                    }
                    func transformedY(_ p: MKMapPoint) -> CGFloat {
                        offsetY + CGFloat(p.y - paddedUnionRect.origin.y) * scale
                    }
                    
                    if let polygons = dependencies.stateBoundaryService.statePolygons[state] {
                        for polygon in polygons {
                            var path = Path()
                            let count = polygon.pointCount
                            guard count > 0 else { continue }
                            let pts = polygon.points()
                            let firstPoint = pts[0]
                            
                            path.move(to: CGPoint(x: transformedX(firstPoint),
                                                  y: transformedY(firstPoint)))
                            for i in 1..<count {
                                let mp = pts[i]
                                path.addLine(to: CGPoint(x: transformedX(mp), y: transformedY(mp)))
                            }
                            path.closeSubpath()
                            
                            context.fill(path, with: .color(fillColor))
                            context.stroke(path, with: .color(strokeColor), lineWidth: SharePreviewView.borderLineWidth)
                        }
                    }
                }
            }
            // Use explicit background to ensure opacity
            .background(backgroundColor)
        }
        .onAppear {
            setupSubscriptions()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }
    
    private func setupSubscriptions() {
        // IMPORTANT FIX: Get current values first
        fillColor = dependencies.settingsService.stateFillColor.value
        strokeColor = dependencies.settingsService.stateStrokeColor.value
        backgroundColor = dependencies.settingsService.backgroundColor.value
        
        // Then subscribe to future changes
        dependencies.settingsService.stateFillColor
            .sink { color in
                self.fillColor = color
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.stateStrokeColor
            .sink { color in
                self.strokeColor = color
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.backgroundColor
            .sink { color in
                self.backgroundColor = color
            }
            .store(in: &cancellables)
    }
    
    func computeUnionMapRectForState(state: String) -> MKMapRect? {
        var unionRect: MKMapRect?
        if let polygons = dependencies.stateBoundaryService.statePolygons[state] {
            for poly in polygons {
                unionRect = unionRect?.union(poly.boundingMapRect) ?? poly.boundingMapRect
            }
        }
        return unionRect
    }
}

// MARK: - ShareInsetStateView

struct ShareInsetStateView: View {
    let stateName: String
    @EnvironmentObject var dependencies: AppDependencies
    
    // Local state
    @State private var fillColor: Color = .red
    @State private var strokeColor: Color = .white
    @State private var backgroundColor: Color = .white
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                if let mapRect = SharePreviewView.preferredMapRects[stateName] {
                    drawState(mapRect: mapRect, size: size, context: &context)
                }
                else if let unionRect = computeUnionRect(for: stateName) {
                    drawState(mapRect: unionRect, size: size, context: &context)
                }
            }
            // Use explicit background to ensure opacity
            .background(backgroundColor)
        }
        .onAppear {
            setupSubscriptions()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }
    
    private func setupSubscriptions() {
        // IMPORTANT FIX: Get current values first
        fillColor = dependencies.settingsService.stateFillColor.value
        strokeColor = dependencies.settingsService.stateStrokeColor.value
        backgroundColor = dependencies.settingsService.backgroundColor.value
        
        // Then subscribe to future changes
        dependencies.settingsService.stateFillColor
            .sink { color in
                self.fillColor = color
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.stateStrokeColor
            .sink { color in
                self.strokeColor = color
            }
            .store(in: &cancellables)
            
        dependencies.settingsService.backgroundColor
            .sink { color in
                self.backgroundColor = color
            }
            .store(in: &cancellables)
    }
    
    private func computeUnionRect(for state: String) -> MKMapRect? {
        guard let polygons = dependencies.stateBoundaryService.statePolygons[stateName] else { return nil }
        var unionRect: MKMapRect?
        for poly in polygons {
            unionRect = unionRect?.union(poly.boundingMapRect) ?? poly.boundingMapRect
        }
        return unionRect
    }
    
    private func drawState(mapRect: MKMapRect, size: CGSize, context: inout GraphicsContext) {
        let extraPaddingFraction: Double = 0.02
        let extraDx = mapRect.size.width * extraPaddingFraction
        let extraDy = mapRect.size.height * extraPaddingFraction
        let paddedRect = mapRect.insetBy(dx: -extraDx, dy: -extraDy)
        
        let scaleX = size.width / CGFloat(paddedRect.size.width)
        let scaleY = size.height / CGFloat(paddedRect.size.height)
        let scale = min(scaleX, scaleY)
        
        let offsetX = (size.width - (paddedRect.size.width * scale)) / 2
        let offsetY = (size.height - (paddedRect.size.height * scale)) / 2
        
        func tx(_ p: MKMapPoint) -> CGFloat {
            offsetX + CGFloat(p.x - paddedRect.origin.x) * scale
        }
        func ty(_ p: MKMapPoint) -> CGFloat {
            offsetY + CGFloat(p.y - paddedRect.origin.y) * scale
        }
        
        if let polygons = dependencies.stateBoundaryService.statePolygons[stateName] {
            for polygon in polygons {
                var path = Path()
                let count = polygon.pointCount
                guard count > 0 else { continue }
                let pts = polygon.points()
                let firstPt = pts[0]
                
                path.move(to: CGPoint(x: tx(firstPt), y: ty(firstPt)))
                for i in 1..<count {
                    let mp = pts[i]
                    path.addLine(to: CGPoint(x: tx(mp), y: ty(mp)))
                }
                path.closeSubpath()
                
                context.fill(path, with: .color(fillColor))
                context.stroke(path, with: .color(strokeColor), lineWidth: SharePreviewView.borderLineWidth)
            }
        }
    }
}
