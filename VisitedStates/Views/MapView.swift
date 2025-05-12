import SwiftUI
import MapKit
import Combine

struct MapView: View {
    // Access app dependencies
    @EnvironmentObject var dependencies: AppDependencies
    
    // Local state
    @State private var visitedStates: [String] = []
    @State private var stateFillColor: Color = .red
    @State private var stateStrokeColor: Color = .white
    @State private var backgroundColor: Color = .white
    @State private var cancellables = Set<AnyCancellable>()
    
    // Constants
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
        ZStack {
            // Background with settings
            backgroundColor
                .edgesIgnoringSafeArea(.all)
            
            GeometryReader { geometry in
                // Exclude D.C. from count for share stats
                let visitedStatesExcludingDC = visitedStates.filter { $0 != "District of Columbia" }
                let visitedCount = visitedStatesExcludingDC.count
                
                let showAlaska = visitedStates.contains("Alaska")
                let showHawaii = visitedStates.contains("Hawaii")
                
                // Debug to check colors when states change
                let _ = print("🗺️ MapView rendering with stateFillColor: \(stateFillColor), visitedStates: \(visitedStates.count)")
                
                // For drawing, use all visitedStates (so D.C. is drawn if visited)
                let contiguousStates = visitedStates.filter { $0 != "Alaska" && $0 != "Hawaii" }
                let noContiguousStates = contiguousStates.isEmpty
                
                if visitedCount == 2 && showAlaska && showHawaii && noContiguousStates {
                    VStack(spacing: 0) {
                        InsetStateView(
                            stateName: "Alaska",
                            fillColor: $stateFillColor,
                            strokeColor: $stateStrokeColor,
                            backgroundColor: $backgroundColor
                        )
                        .environmentObject(dependencies)
                        .frame(width: geometry.size.width, height: geometry.size.height / 2)
                        
                        InsetStateView(
                            stateName: "Hawaii",
                            fillColor: $stateFillColor,
                            strokeColor: $stateStrokeColor,
                            backgroundColor: $backgroundColor
                        )
                        .environmentObject(dependencies)
                        .frame(width: geometry.size.width, height: geometry.size.height / 2)
                    }
                } else if visitedCount == 1 && (showAlaska || showHawaii) && noContiguousStates {
                    if showAlaska {
                        FullScreenStateView(state: "Alaska")
                            .environmentObject(dependencies)
                    } else {
                        FullScreenStateView(state: "Hawaii")
                            .environmentObject(dependencies)
                    }
                } else {
                    let insetsCount = (showAlaska ? 1 : 0) + (showHawaii ? 1 : 0)
                    let boxSize: CGFloat = geometry.size.width * 0.375
                    
                    ZStack(alignment: .bottomLeading) {
                        ContiguousStatesCanvas(visitedStates: contiguousStates)
                            .environmentObject(dependencies)
                            .frame(width: geometry.size.width, height: geometry.size.height * 0.6)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        if insetsCount > 0 {
                            if showAlaska && showHawaii {
                                HStack(spacing: 0) {
                                    InsetStateView(
                                        stateName: "Alaska",
                                        fillColor: $stateFillColor,
                                        strokeColor: $stateStrokeColor,
                                        backgroundColor: $backgroundColor
                                    )
                                    .environmentObject(dependencies)
                                    .frame(width: boxSize, height: boxSize)
                                    
                                    InsetStateView(
                                        stateName: "Hawaii",
                                        fillColor: $stateFillColor,
                                        strokeColor: $stateStrokeColor,
                                        backgroundColor: $backgroundColor
                                    )
                                    .environmentObject(dependencies)
                                    .frame(width: boxSize, height: boxSize)
                                }
                                .padding([.leading, .bottom], 8)
                            } else if showAlaska {
                                InsetStateView(
                                    stateName: "Alaska",
                                    fillColor: $stateFillColor,
                                    strokeColor: $stateStrokeColor,
                                    backgroundColor: $backgroundColor
                                )
                                .environmentObject(dependencies)
                                .frame(width: boxSize, height: boxSize)
                                .padding([.leading, .bottom], 8)
                            } else if showHawaii {
                                InsetStateView(
                                    stateName: "Hawaii",
                                    fillColor: $stateFillColor,
                                    strokeColor: $stateStrokeColor,
                                    backgroundColor: $backgroundColor
                                )
                                .environmentObject(dependencies)
                                .frame(width: boxSize, height: boxSize)
                                .padding([.leading, .bottom], 8)
                            }
                        }
                    }
                }
                
                let labelText = "\(visitedCount)/50 States Visited"
                VStack(spacing: 2) {
                    Text(labelText)
                        .foregroundColor(.gray)
                        .font(.custom("DoHyeon-Regular", size: 20))

                    #if DEBUG
                    // This will ONLY show in debug/development builds
                    Text("Development Build")
                        .foregroundColor(.red)
                        .font(.custom("DoHyeon-Regular", size: 20))
                    #endif
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.2)
            }
        }
        .onAppear {
            setupSubscriptions()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }
    
    private func setupSubscriptions() {
        // Get initial values first to ensure state and colors are in sync
        stateFillColor = dependencies.settingsService.stateFillColor.value
        stateStrokeColor = dependencies.settingsService.stateStrokeColor.value
        backgroundColor = dependencies.settingsService.backgroundColor.value
        visitedStates = dependencies.settingsService.visitedStates.value
        
        // Subscribe to visited states changes
        dependencies.settingsService.visitedStates
            .sink { states in
                // When states change, force refresh all color values too
                // to ensure newly added states use the current colors
                self.visitedStates = states
                self.stateFillColor = self.dependencies.settingsService.stateFillColor.value
                self.stateStrokeColor = self.dependencies.settingsService.stateStrokeColor.value
                self.backgroundColor = self.dependencies.settingsService.backgroundColor.value
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
    
    @MainActor
    func takeSnapshot(size: CGSize) async -> UIImage? {
        let renderer = ImageRenderer(content: self.frame(width: size.width, height: size.height))
        return renderer.uiImage
    }
}

// MARK: - ContiguousStatesCanvas

struct ContiguousStatesCanvas: View {
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
                            context.stroke(path, with: .color(strokeColor), lineWidth: MapView.borderLineWidth)
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
        .background(backgroundColor)
    }
    
    private func setupSubscriptions() {
        // IMPORTANT FIX: Get current values first
        fillColor = dependencies.settingsService.stateFillColor.value
        strokeColor = dependencies.settingsService.stateStrokeColor.value
        backgroundColor = dependencies.settingsService.backgroundColor.value
        
        // Subscribe to color changes
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

// MARK: - FullScreenStateView

struct FullScreenStateView: View {
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
                if let mapRect = MapView.preferredMapRects[state] {
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
                            context.stroke(path, with: .color(strokeColor), lineWidth: MapView.borderLineWidth)
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
                            context.stroke(path, with: .color(strokeColor), lineWidth: MapView.borderLineWidth)
                        }
                    }
                }
            }
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

// MARK: - InsetStateView

struct InsetStateView: View {
    let stateName: String
    @EnvironmentObject var dependencies: AppDependencies
    
    // Colors received as environment values from parent
    @Environment(\.colorScheme) var colorScheme
    
    // Local state
    @Binding var parentFillColor: Color
    @Binding var parentStrokeColor: Color
    @Binding var parentBackgroundColor: Color
    
    // Initialize with default colors to keep backward compatibility
    init(stateName: String, fillColor: Binding<Color>? = nil, strokeColor: Binding<Color>? = nil, backgroundColor: Binding<Color>? = nil) {
        self.stateName = stateName
        self._parentFillColor = fillColor ?? .constant(.red)
        self._parentStrokeColor = strokeColor ?? .constant(.white)
        self._parentBackgroundColor = backgroundColor ?? .constant(.white)
    }
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                if let mapRect = MapView.preferredMapRects[stateName] {
                    drawState(mapRect: mapRect, size: size, context: &context)
                }
                else if let unionRect = computeUnionRect(for: stateName) {
                    drawState(mapRect: unionRect, size: size, context: &context)
                }
            }
            .background(parentBackgroundColor)
        }
        .onAppear {
            // Debug: Log inset view appearance with color information
            if stateName == "Alaska" {
                print("🟢 Showing InsetStateView for Alaska with fillColor: \(parentFillColor)")
            } else if stateName == "Hawaii" {
                print("🟢 Showing InsetStateView for Hawaii with fillColor: \(parentFillColor)")
            }
        }
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
                
                context.fill(path, with: .color(parentFillColor))
                context.stroke(path, with: .color(parentStrokeColor), lineWidth: MapView.borderLineWidth)
            }
        }
    }
}
