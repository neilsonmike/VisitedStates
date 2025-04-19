import Foundation
import MapKit

class StateBoundaryService: StateBoundaryServiceProtocol {
    // MARK: - Properties
    
    var statePolygons: [String: [MKPolygon]] = [:]
    private var isLoaded = false
    private var stateQuadTree: QuadTree?
    private var stateBorders: [StateBorder] = []
    
    // Cache for state lookup
    private var stateNameCache: [CacheKey: String?] = [:]
    private let cacheSize = 100
    
    // MARK: - Initialization
    
    init() {
        loadBoundaryData()
    }
    
    // MARK: - StateBoundaryServiceProtocol
    
    func stateName(for coordinate: CLLocationCoordinate2D) -> String? {
        // Check if boundaries are loaded
        guard isLoaded else {
            print("⚠️ Boundary data not loaded yet")
            loadBoundaryData()
            return nil
        }
        
        // First, check the cache
        let cacheKey = CacheKey(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let cachedState = stateNameCache[cacheKey] {
            return cachedState
        }
        
        // If we have a quad tree, use it for fast preliminary filtering
        if let quadTree = stateQuadTree {
            let point = MKMapPoint(coordinate)
            let items = quadTree.items(at: point)
            
            // Check if the coordinate is within any of the filtered state polygons
            for stateItem in items {
                if stateItem.polygon.contains(coordinate: coordinate) {
                    // Cache the result
                    stateNameCache[cacheKey] = stateItem.stateName
                    
                    // Limit cache size
                    if stateNameCache.count > cacheSize {
                        // Dictionary doesn't have removeFirst, we need to remove a random key
                        if let firstKey = stateNameCache.keys.first {
                            stateNameCache.removeValue(forKey: firstKey)
                        }
                    }
                    
                    return stateItem.stateName
                }
            }
        } else {
            // Fallback to brute force search if quad tree not available
            for (state, polygons) in statePolygons {
                for polygon in polygons {
                    if polygon.contains(coordinate: coordinate) {
                        // Cache the result
                        stateNameCache[cacheKey] = state
                        
                        // Limit cache size
                        if stateNameCache.count > cacheSize {
                            // Dictionary doesn't have removeFirst, we need to remove a random key
                            if let firstKey = stateNameCache.keys.first {
                                stateNameCache.removeValue(forKey: firstKey)
                            }
                        }
                        
                        return state
                    }
                }
            }
        }
        
        // Cache negative result as well
        stateNameCache[cacheKey] = nil
        
        // Limit cache size
        if stateNameCache.count > cacheSize {
            // Dictionary doesn't have removeFirst, we need to remove a random key
            if let firstKey = stateNameCache.keys.first {
                stateNameCache.removeValue(forKey: firstKey)
            }
        }
        
        return nil
    }
    
    func getStateBorders() -> [StateBorder] {
        return stateBorders
    }
    
    func loadBoundaryData() {
        // Only load once
        guard !isLoaded else { return }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let url = Bundle.main.url(forResource: "us_states", withExtension: "geojson") else {
            print("❌ Error: us_states.geojson file not found in bundle.")
            return
        }
        
        print("🔍 Loading GeoJSON file...")
        
        do {
            let data = try Data(contentsOf: url)
            let geoJSONObjects = try MKGeoJSONDecoder().decode(data)
            
            // Initialize quad tree with US bounding box
            let usBounds = MKMapRect(
                x: 0,
                y: 0,
                width: MKMapSize.world.width,
                height: MKMapSize.world.height
            )
            stateQuadTree = QuadTree(region: usBounds, capacity: 8)
            
            for item in geoJSONObjects {
                if let feature = item as? MKGeoJSONFeature,
                   let propertiesData = feature.properties,
                   let properties = try? JSONSerialization.jsonObject(with: propertiesData) as? [String: Any],
                   let stateName = properties["NAME"] as? String {
                    
                    for geometry in feature.geometry {
                        if let polygon = geometry as? MKPolygon {
                            statePolygons[stateName, default: []].append(polygon)
                            
                            // Add to quad tree
                            if let quadTree = stateQuadTree {
                                let item = QuadTreeItem(
                                    mapRect: polygon.boundingMapRect,
                                    stateName: stateName,
                                    polygon: polygon
                                )
                                _ = quadTree.insert(item)
                            }
                            
                            // Process border for this polygon
                            extractStateBorder(polygon, for: stateName)
                        } else if let multiPolygon = geometry as? MKMultiPolygon {
                            let polygons = extractPolygons(from: multiPolygon, for: stateName)
                            
                            // Add each extracted polygon to quad tree
                            if let quadTree = stateQuadTree {
                                for polygon in polygons {
                                    let item = QuadTreeItem(
                                        mapRect: polygon.boundingMapRect,
                                        stateName: stateName,
                                        polygon: polygon
                                    )
                                    _ = quadTree.insert(item)
                                }
                            }
                        }
                    }
                }
            }
            
            isLoaded = true
            let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ GeoJSON file decoded successfully in \(elapsedTime) seconds.")
            print("📍 Loaded \(statePolygons.count) states from GeoJSON.")
            print("🗺️ Created quad tree with items")
            print("🛣️ Extracted \(stateBorders.count) state borders")
        } catch {
            print("❌ Error decoding GeoJSON: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private methods
    
    private func extractPolygons(from multiPolygon: MKMultiPolygon, for stateName: String) -> [MKPolygon] {
        var extractedPolygons: [MKPolygon] = []
        
        // Different handling depending on iOS version
        if #available(iOS 14.0, *) {
            // For iOS 14+, we can use the polygons property
            for polygon in multiPolygon.polygons {
                statePolygons[stateName, default: []].append(polygon)
                extractedPolygons.append(polygon)
                
                // Process border for this polygon
                extractStateBorder(polygon, for: stateName)
            }
        } else {
            // Fallback for earlier iOS versions
            // This is a less elegant approach using KVC, but works
            if let polygonsArray = multiPolygon.value(forKey: "polygons") as? [MKPolygon] {
                statePolygons[stateName, default: []].append(contentsOf: polygonsArray)
                extractedPolygons.append(contentsOf: polygonsArray)
                
                // Process border for each polygon
                for polygon in polygonsArray {
                    extractStateBorder(polygon, for: stateName)
                }
            }
        }
        
        return extractedPolygons
    }
    
    private func extractStateBorder(_ polygon: MKPolygon, for stateName: String) {
        // Extract points from the polygon to represent the border
        let pointCount = polygon.pointCount
        guard pointCount > 0 else { return }
        
        let points = polygon.points()
        
        // For simplicity, we'll sample points from the polygon to create the border
        // In a production app, you might use a more sophisticated algorithm
        
        // Sample every nth point to reduce data size
        let sampleRate = max(1, pointCount / 20) // Aim for about 20 points per polygon
        
        var borderPoints: [CLLocationCoordinate2D] = []
        
        for i in stride(from: 0, to: pointCount, by: sampleRate) {
            let mapPoint = points[i]
            let coordinate = mapPoint.coordinate
            borderPoints.append(coordinate)
        }
        
        // Create and store the border
        if borderPoints.count >= 3 {
            let border = StateBorder(stateName: stateName, coordinates: borderPoints)
            stateBorders.append(border)
        }
    }
}

// MARK: - MKPolygon Extension

extension MKPolygon {
    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        let mapPoint = MKMapPoint(coordinate)
        let renderer = MKPolygonRenderer(polygon: self)
        guard let path = renderer.path else { return false }
        let point = renderer.point(for: mapPoint)
        return path.contains(point)
    }
}

// MARK: - State Border Structure

struct StateBorder {
    let stateName: String
    let coordinates: [CLLocationCoordinate2D]
    
    // Calculate distance from a coordinate to this border
    func distanceTo(_ coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        var minDistance: CLLocationDistance = .greatestFiniteMagnitude
        
        // Create a location from the input coordinate
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Check each border segment
        for i in 0..<(coordinates.count - 1) {
            let start = coordinates[i]
            let end = coordinates[i+1]
            
            let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
            
            // Calculate distance to line segment
            let distance = distanceToLineSegment(from: location, lineStart: startLocation, lineEnd: endLocation)
            
            minDistance = min(minDistance, distance)
        }
        
        return minDistance
    }
    
    private func distanceToLineSegment(from point: CLLocation, lineStart: CLLocation, lineEnd: CLLocation) -> CLLocationDistance {
        // Calculate distance from point to line segment
        // This is a simplified implementation for demonstration
        
        let startToPoint = CLLocation(
            latitude: point.coordinate.latitude - lineStart.coordinate.latitude,
            longitude: point.coordinate.longitude - lineStart.coordinate.longitude
        )
        
        let startToEnd = CLLocation(
            latitude: lineEnd.coordinate.latitude - lineStart.coordinate.latitude,
            longitude: lineEnd.coordinate.longitude - lineStart.coordinate.longitude
        )
        
        // Project point onto line
        let projection = (startToPoint.coordinate.latitude * startToEnd.coordinate.latitude +
                          startToPoint.coordinate.longitude * startToEnd.coordinate.longitude)
        
        let lineLengthSquared = (startToEnd.coordinate.latitude * startToEnd.coordinate.latitude +
                                startToEnd.coordinate.longitude * startToEnd.coordinate.longitude)
        
        if lineLengthSquared < 1e-10 {
            // Line segment is too short, just return distance to start point
            return point.distance(from: lineStart)
        }
        
        let ratio = max(0, min(1, projection / lineLengthSquared))
        
        // Create the closest point on the line
        let closestPoint = CLLocation(
            latitude: lineStart.coordinate.latitude + ratio * startToEnd.coordinate.latitude,
            longitude: lineStart.coordinate.longitude + ratio * startToEnd.coordinate.longitude
        )
        
        // Return distance to closest point
        return point.distance(from: closestPoint)
    }
}

// MARK: - Cache Key

struct CacheKey: Hashable {
    let latitude: Double
    let longitude: Double
    
    // Round coordinates to reduce cache size while maintaining accuracy
    init(latitude: Double, longitude: Double) {
        // Round to 4 decimal places (about 11 meters of precision)
        self.latitude = round(latitude * 10000) / 10000
        self.longitude = round(longitude * 10000) / 10000
    }
}

// MARK: - Quad Tree Implementation

class QuadTreeItem {
    let mapRect: MKMapRect
    let stateName: String
    let polygon: MKPolygon
    
    init(mapRect: MKMapRect, stateName: String, polygon: MKPolygon) {
        self.mapRect = mapRect
        self.stateName = stateName
        self.polygon = polygon
    }
}

class QuadTree {
    private let region: MKMapRect
    private let capacity: Int
    private var items: [QuadTreeItem] = []
    private var hasSubdivided = false
    
    // Four children for subdivision
    private var northEast: QuadTree?
    private var northWest: QuadTree?
    private var southEast: QuadTree?
    private var southWest: QuadTree?
    
    init(region: MKMapRect, capacity: Int) {
        self.region = region
        self.capacity = capacity
    }
    
    func insert(_ item: QuadTreeItem) -> Bool {
        // Check if this item's rect intersects with this node's region
        if !region.intersects(item.mapRect) {
            return false
        }
        
        if items.count < capacity && !hasSubdivided {
            items.append(item)
            return true
        }
        
        // Need to subdivide if we haven't already
        if !hasSubdivided {
            subdivide()
        }
        
        // Try to insert in all four quadrants (can overlap multiple)
        var inserted = false
        
        if let ne = northEast, ne.insert(item) {
            inserted = true
        }
        
        if let nw = northWest, nw.insert(item) {
            inserted = true
        }
        
        if let se = southEast, se.insert(item) {
            inserted = true
        }
        
        if let sw = southWest, sw.insert(item) {
            inserted = true
        }
        
        return inserted
    }
    
    func items(at point: MKMapPoint) -> [QuadTreeItem] {
        // Check if point is within this node's region
        if !region.contains(point) {
            return []
        }
        
        var result: [QuadTreeItem] = []
        
        // Add items at this level that contain the point
        for item in items {
            if item.mapRect.contains(point) {
                result.append(item)
            }
        }
        
        // If subdivided, check children
        if hasSubdivided {
            if let ne = northEast {
                result.append(contentsOf: ne.items(at: point))
            }
            
            if let nw = northWest {
                result.append(contentsOf: nw.items(at: point))
            }
            
            if let se = southEast {
                result.append(contentsOf: se.items(at: point))
            }
            
            if let sw = southWest {
                result.append(contentsOf: sw.items(at: point))
            }
        }
        
        return result
    }
    
    private func subdivide() {
        let x = region.origin.x
        let y = region.origin.y
        let halfWidth = region.size.width / 2
        let halfHeight = region.size.height / 2
        
        // Create four child nodes
        let neRect = MKMapRect(origin: MKMapPoint(x: x + halfWidth, y: y), size: MKMapSize(width: halfWidth, height: halfHeight))
        northEast = QuadTree(region: neRect, capacity: capacity)
        
        let nwRect = MKMapRect(origin: MKMapPoint(x: x, y: y), size: MKMapSize(width: halfWidth, height: halfHeight))
        northWest = QuadTree(region: nwRect, capacity: capacity)
        
        let seRect = MKMapRect(origin: MKMapPoint(x: x + halfWidth, y: y + halfHeight), size: MKMapSize(width: halfWidth, height: halfHeight))
        southEast = QuadTree(region: seRect, capacity: capacity)
        
        let swRect = MKMapRect(origin: MKMapPoint(x: x, y: y + halfHeight), size: MKMapSize(width: halfWidth, height: halfHeight))
        southWest = QuadTree(region: swRect, capacity: capacity)
        
        // Move items to children
        for item in items {
            // Try to insert in all four quadrants as needed
            _ = northEast?.insert(item)
            _ = northWest?.insert(item)
            _ = southEast?.insert(item)
            _ = southWest?.insert(item)
        }
        
        // Clear this node's items since they've been moved to children
        items.removeAll()
        hasSubdivided = true
    }
}
