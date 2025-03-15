import SwiftUI
import MapKit

// MARK: - StateBoundaryManager

class StateBoundaryManager {
    static let shared = StateBoundaryManager()
    var statePolygons: [String: [MKPolygon]] = [:]
    
    private init() {
        loadGeoJSON()
    }
    
    func stateName(for coordinate: CLLocationCoordinate2D) -> String? {
        for (state, polygons) in statePolygons {
            for polygon in polygons {
                if polygon.contains(coordinate: coordinate) {
                    return state
                }
            }
        }
        return nil
    }

    private func loadGeoJSON() {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let url = Bundle.main.url(forResource: "us_states", withExtension: "geojson") else {
            print("us_states.geojson file not found in bundle.")
            print("GeoJSON file loading failed.")
            return
        }
        
        print("🔍 Loading GeoJSON file...")
        
        do {
            let data = try Data(contentsOf: url)
            let geoJSONObjects = try MKGeoJSONDecoder().decode(data)
            
            for item in geoJSONObjects {
                if let feature = item as? MKGeoJSONFeature,
                   let propertiesData = feature.properties,
                   let properties = try? JSONSerialization.jsonObject(with: propertiesData) as? [String: Any],
                   let stateName = properties["NAME"] as? String {
                    
                    for geometry in feature.geometry {
                        if let polygon = geometry as? MKPolygon {
                            statePolygons[stateName, default: []].append(polygon)
                        } else if let multiPolygon = geometry as? MKMultiPolygon {
                            statePolygons[stateName, default: []].append(contentsOf: multiPolygon.polygons)
                        }
                    }
                }
            }
            
            let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ GeoJSON file decoded successfully in \(elapsedTime) seconds.")
            print("📍 Loaded \(statePolygons.count) states from GeoJSON.")
        } catch {
            print("❌ Error decoding GeoJSON: \(error.localizedDescription)")
        }
    }
}

extension MKPolygon {
    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        let mapPoint = MKMapPoint(coordinate)
        let renderer = MKPolygonRenderer(polygon: self)
        guard let path = renderer.path else { return false }
        let point = renderer.point(for: mapPoint)
        return path.contains(point)
    }
}

// MARK: - MapView

struct MapView: View {
    @Binding var visitedStates: [String]
    @EnvironmentObject var settings: AppSettings
    
    // A constant border thickness for all states
    static let borderLineWidth: CGFloat = 0.5

    // We'll reference "California alone" as the baseline for scale
    static let californiaCenter = CLLocationCoordinate2D(latitude: 37.3, longitude: -119.5)
    static let californiaSpan   = MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0)
    
    static let referenceScale: CGFloat = {
        let refRect = regionToMapRect(center: californiaCenter, span: californiaSpan)
        let extraPaddingFraction: Double = 0.02
        let extraDx = refRect.size.width * extraPaddingFraction
        let extraDy = refRect.size.height * extraPaddingFraction
        let paddedRect = refRect.insetBy(dx: -extraDx, dy: -extraDy)
        
        let testWidth:  CGFloat = 400
        let testHeight: CGFloat = 400
        let scaleX = testWidth  / CGFloat(paddedRect.size.width)
        let scaleY = testHeight / CGFloat(paddedRect.size.height)
        return min(scaleX, scaleY)
    }()
    
    static func regionToMapRect(center: CLLocationCoordinate2D, span: MKCoordinateSpan) -> MKMapRect {
        let centerPoint = MKMapPoint(center)
        let widthMeters  = span.longitudeDelta * 111_000.0
        let heightMeters = span.latitudeDelta  * 111_000.0
        let origin = MKMapPoint(x: centerPoint.x - widthMeters / 2,
                                y: centerPoint.y - heightMeters / 2)
        return MKMapRect(origin: origin,
                         size: MKMapSize(width: widthMeters, height: heightMeters))
    }

    static let preferredMapRects: [String: MKMapRect] = {
        func regionToMapRect(center: CLLocationCoordinate2D, span: MKCoordinateSpan) -> MKMapRect {
            let centerPoint = MKMapPoint(center)
            let widthMeters  = span.longitudeDelta * 111_000.0
            let heightMeters = span.latitudeDelta  * 111_000.0
            let origin = MKMapPoint(x: centerPoint.x - widthMeters / 2,
                                    y: centerPoint.y - heightMeters / 2)
            return MKMapRect(origin: origin,
                             size: MKMapSize(width: widthMeters, height: heightMeters))
        }
        
        let alaskaRect = regionToMapRect(
            center: CLLocationCoordinate2D(latitude: 64.0, longitude: -152.0),
            span: MKCoordinateSpan(latitudeDelta: 275.0, longitudeDelta: 275.0)
        )
        let hawaiiRect = regionToMapRect(
            center: CLLocationCoordinate2D(latitude: 20.7, longitude: -156.5),
            span: MKCoordinateSpan(latitudeDelta: 4.0,  longitudeDelta: 30.0)
        )
        
        return [
            "Alaska": alaskaRect,
            "Hawaii": hawaiiRect
        ]
    }()
    
    var body: some View {
    ZStack {
            GeometryReader { geometry in
                
                // Exclude DC from the count only:
                let visitedStatesExcludingDC = visitedStates.filter { $0 != "District of Columbia" }
                let visitedCount = visitedStatesExcludingDC.count
                
                let showAlaska = visitedStates.contains("Alaska")
                let showHawaii = visitedStates.contains("Hawaii")
                
                // For actual drawing, we still use "visitedStates"
                // so DC is drawn if visited
                let contiguousStates = visitedStates.filter { $0 != "Alaska" && $0 != "Hawaii" }
                let noContiguousStates = contiguousStates.isEmpty
                
                if visitedCount == 2 && showAlaska && showHawaii && noContiguousStates {
                    // 2 visited states are AK + HI, no contiguous
                    VStack(spacing: 0) {
                        InsetStateView(stateName: "Alaska")
                            .environmentObject(settings)
                            .frame(width: geometry.size.width, height: geometry.size.height / 2)
                        
                        InsetStateView(stateName: "Hawaii")
                            .environmentObject(settings)
                            .frame(width: geometry.size.width, height: geometry.size.height / 2)
                    }
                }
                else if visitedCount == 1 && (showAlaska || showHawaii) && noContiguousStates {
                    // 1 visited, AK or HI only
                    if showAlaska {
                        FullScreenStateView(state: "Alaska")
                            .environmentObject(settings)
                    } else {
                        FullScreenStateView(state: "Hawaii")
                            .environmentObject(settings)
                    }
                }
                else {
                    // Might have contiguous states plus possibly AK or HI
                    let insetsCount = (showAlaska ? 1 : 0) + (showHawaii ? 1 : 0)
                    let boxSize: CGFloat = geometry.size.width * 0.375
                    
                    ZStack(alignment: .bottomLeading) {
                        // Use "contiguousStates" to draw the lower 48, but DC is included here if it’s in visited
                        ContiguousStatesCanvas(
                            visitedStates: contiguousStates,
                            totalSize: CGSize(width: geometry.size.width, height: geometry.size.height)
                        )
                        .environmentObject(settings)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        
                        if insetsCount > 0 {
                            if showAlaska && showHawaii {
                                HStack(spacing: 0) {
                                    InsetStateView(stateName: "Alaska")
                                        .environmentObject(settings)
                                        .frame(width: boxSize, height: boxSize)
                                    
                                    InsetStateView(stateName: "Hawaii")
                                        .environmentObject(settings)
                                        .frame(width: boxSize, height: boxSize)
                                }
                                .padding([.leading, .bottom], 8)
                            }
                            else if showAlaska {
                                InsetStateView(stateName: "Alaska")
                                    .environmentObject(settings)
                                    .frame(width: boxSize, height: boxSize)
                                    .padding([.leading, .bottom], 8)
                            }
                            else if showHawaii {
                                InsetStateView(stateName: "Hawaii")
                                    .environmentObject(settings)
                                    .frame(width: boxSize, height: boxSize)
                                    .padding([.leading, .bottom], 8)
                            }
                        }
                    }
                }
                
                // Display stats label "XX/50 States Visited"
                let labelText = "\(visitedCount)/50 States Visited"
                Text(labelText)
                    .foregroundColor(.gray)
                    .font(.custom("DoHyeon-Regular", size: 16))
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.2)
            }
        }
    }
    
    @MainActor
    func takeSnapshot(size: CGSize) async -> UIImage? {
        let renderer = ImageRenderer(content: self.frame(width: size.width, height: size.height))
        return renderer.uiImage
    }
}
// MARK: - ContiguousStatesCanvas

struct ContiguousStatesCanvas: View {
    @EnvironmentObject var settings: AppSettings
    let visitedStates: [String]
    let totalSize: CGSize
    
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
                
                let fillColor   = settings.stateFillColor
                let strokeColor = settings.stateStrokeColor
                
                for state in visitedStates {
                    if let polygons = StateBoundaryManager.shared.statePolygons[state] {
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
            // Debug: ContiguousStatesCanvas rendering
            print("🟢 Rendering ContiguousStatesCanvas")
        }
        .background(settings.backgroundColor)
    }
    
    func computeUnionMapRect(for states: [String]) -> MKMapRect? {
        var unionRect: MKMapRect?
        for state in states {
            if let polys = StateBoundaryManager.shared.statePolygons[state] {
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
    @EnvironmentObject var settings: AppSettings

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
                    
                    if let polygons = StateBoundaryManager.shared.statePolygons[state] {
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
                            
                            context.fill(path, with: .color(settings.stateFillColor))
                            context.stroke(path, with: .color(settings.stateStrokeColor), lineWidth: MapView.borderLineWidth)
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
                    
                    let drawnWidth  = CGFloat(paddedUnionRect.size.width)  * scale
                    let drawnHeight = CGFloat(paddedUnionRect.size.height) * scale
                    
                    let offsetX = (size.width  - drawnWidth)  / 2
                    let offsetY = (size.height - drawnHeight) / 2
                    
                    func transformedX(_ p: MKMapPoint) -> CGFloat {
                        offsetX + CGFloat(p.x - paddedUnionRect.origin.x) * scale
                    }
                    func transformedY(_ p: MKMapPoint) -> CGFloat {
                        offsetY + CGFloat(p.y - paddedUnionRect.origin.y) * scale
                    }
                    
                    if let polygons = StateBoundaryManager.shared.statePolygons[state] {
                        for polygon in polygons {
                            var path = Path()
                            let pointCount = polygon.pointCount
                            guard pointCount > 0 else { continue }
                            let points = polygon.points()
                            let firstPoint = points[0]
                            
                            path.move(to: CGPoint(x: transformedX(firstPoint),
                                                  y: transformedY(firstPoint)))
                            for i in 1..<pointCount {
                                let mp = points[i]
                                path.addLine(to: CGPoint(x: transformedX(mp), y: transformedY(mp)))
                            }
                            path.closeSubpath()
                            
                            context.fill(path, with: .color(settings.stateFillColor))
                            context.stroke(path, with: .color(settings.stateStrokeColor), lineWidth: MapView.borderLineWidth)
                        }
                    }
                }
            }
            .background(settings.backgroundColor)
        }
    }
    
    func computeUnionMapRectForState(state: String) -> MKMapRect? {
        var unionRect: MKMapRect?
        if let polygons = StateBoundaryManager.shared.statePolygons[state] {
            for poly in polygons {
                if unionRect == nil {
                    unionRect = poly.boundingMapRect
                } else {
                    unionRect = unionRect?.union(poly.boundingMapRect)
                }
            }
        }
        return unionRect
    }
}

// MARK: - InsetStateView

struct InsetStateView: View {
    let stateName: String
    @EnvironmentObject var settings: AppSettings
    
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
        .background(settings.backgroundColor)
    }
    .onAppear {
        // Debug: InsetStateView appearance log
        if stateName == "Alaska" {
            print("🟢 Showing InsetStateView for Alaska")
        } else if stateName == "Hawaii" {
            print("🟢 Showing InsetStateView for Hawaii")
        }
    }
    }
    
    private func computeUnionRect(for state: String) -> MKMapRect? {
        guard let polygons = StateBoundaryManager.shared.statePolygons[stateName] else { return nil }
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
        
        if let polygons = StateBoundaryManager.shared.statePolygons[stateName] {
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
                
                let fillColor   = settings.stateFillColor
                let strokeColor = settings.stateStrokeColor
                context.fill(path, with: .color(fillColor))
                
                context.stroke(path, with: .color(strokeColor), lineWidth: MapView.borderLineWidth)
            }
        }
    }
}
