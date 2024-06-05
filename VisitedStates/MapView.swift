import SwiftUI
import MapKit

struct MapView: UIViewRepresentable {
    @Binding var visitedStates: [String]
    var locationManager: LocationManager

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none  // Set to .none to allow custom zooming behavior
        mapView.isUserInteractionEnabled = false  // Disable user interaction
        mapView.isScrollEnabled = false  // Disable scrolling
        mapView.isZoomEnabled = false  // Disable zooming
        mapView.mapType = .standard  // Use standard map type
        mapView.showsBuildings = false  // Hide buildings
        mapView.pointOfInterestFilter = .excludingAll  // Hide points of interest
        mapView.showsCompass = false  // Hide compass
        mapView.showsScale = false  // Hide scale
        mapView.showsTraffic = false  // Hide traffic

        // Adding an empty overlay to initialize the map correctly
        let initialCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)  // Default to San Francisco
        let initialSpan = MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        let initialRegion = MKCoordinateRegion(center: initialCoordinate, span: initialSpan)
        mapView.setRegion(initialRegion, animated: false)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Clear previous overlays
        print("Removing previous overlays")
        uiView.removeOverlays(uiView.overlays)

        var overlays: [MKOverlay] = []

        // Add overlays for visited states
        for state in visitedStates {
            if let overlay = getStateOverlay(for: state) {
                overlays.append(overlay)
                uiView.addOverlay(overlay)
                print("Added overlay for state: \(state)")
            } else {
                print("No overlay found for state: \(state)")
            }
        }

        // Adjust the map region to fit all visited states
        if !overlays.isEmpty {
            let boundingRegion = calculateBoundingRegion(for: overlays)
            // Ensure the region is valid
            if isValidRegion(boundingRegion) {
                print("Setting region: \(boundingRegion)")
                uiView.setRegion(boundingRegion, animated: true)
            } else {
                print("Invalid region calculated, skipping region adjustment")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.red.withAlphaComponent(0.5)
                renderer.strokeColor = UIColor.white
                renderer.lineWidth = 0.5  // Reduced to 25% of the previous value
                return renderer
            } else if let multiPolygon = overlay as? MKMultiPolygon {
                let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
                renderer.fillColor = UIColor.red.withAlphaComponent(0.5)
                renderer.strokeColor = UIColor.white
                renderer.lineWidth = 0.5  // Reduced to 25% of the previous value
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }

    func getStateOverlay(for state: String) -> MKOverlay? {
        guard let geoJSONString = loadGeoJSONData() else {
            print("Failed to load GeoJSON data from file")
            return nil
        }

        guard let data = geoJSONString.data(using: .utf8) else {
            print("Failed to convert JSON string to data")
            return nil
        }

        guard let features = try? MKGeoJSONDecoder().decode(data).compactMap({ $0 as? MKGeoJSONFeature }) else {
            print("Failed to decode GeoJSON data")
            return nil
        }

        var stateNames = [String]()
        for feature in features {
            if let properties = feature.properties,
               let json = try? JSONSerialization.jsonObject(with: properties, options: []) as? [String: Any],
               let stateName = json["NAME"] as? String {
                stateNames.append(stateName)
                print("Parsed state name: \(stateName)")
                if stateName == state {
                    print("Found state: \(stateName)")
                    var allPolygons: [MKPolygon] = []

                    for geometry in feature.geometry {
                        if let polygon = geometry as? MKPolygon {
                            allPolygons.append(polygon)
                            print("Added polygon with \(polygon.pointCount) points for state: \(stateName)")
                        } else if let multiPolygon = geometry as? MKMultiPolygon {
                            allPolygons.append(contentsOf: multiPolygon.polygons)
                            print("Added multiPolygon with \(multiPolygon.polygons.count) polygons for state: \(stateName)")
                        } else {
                            print("Unknown geometry type for state: \(stateName)")
                        }
                    }

                    if allPolygons.count == 1 {
                        return allPolygons.first
                    } else if allPolygons.count > 1 {
                        return MKMultiPolygon(allPolygons)
                    }
                }
            }
        }
        print("State \(state) not found in GeoJSON data. Available states: \(stateNames)")
        return nil
    }

    func calculateBoundingRegion(for overlays: [MKOverlay]) -> MKCoordinateRegion {
        var minLat = CLLocationDegrees(90.0)
        var maxLat = CLLocationDegrees(-90.0)
        var minLon = CLLocationDegrees(180.0)
        var maxLon = CLLocationDegrees(-180.0)

        var containsAlaska = false

        for overlay in overlays {
            if let polygon = overlay as? MKPolygon {
                let points = polygon.points()
                for i in 0..<polygon.pointCount {
                    let coord = points[i].coordinate
                    minLat = min(minLat, coord.latitude)
                    maxLat = max(maxLat, coord.latitude)
                    minLon = min(minLon, coord.longitude)
                    maxLon = max(maxLon, coord.longitude)
                    if coord.longitude > 170 || coord.longitude < -170 {
                        containsAlaska = true
                    }
                }
            } else if let multiPolygon = overlay as? MKMultiPolygon {
                for polygon in multiPolygon.polygons {
                    let points = polygon.points()
                    for i in 0..<polygon.pointCount {
                        let coord = points[i].coordinate
                        minLat = min(minLat, coord.latitude)
                        maxLat = max(maxLat, coord.latitude)
                        minLon = min(minLon, coord.longitude)
                        maxLon = max(maxLon, coord.longitude)
                        if coord.longitude > 170 || coord.longitude < -170 {
                            containsAlaska = true
                        }
                    }
                }
            }
        }

        // Adjust the bounds if Alaska is included
        if containsAlaska {
            maxLat = max(maxLat, 70)
            minLon = min(minLon, -180)
        }

        let centerLat = (minLat + maxLat) / 2
        var centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) * 1.2  // Add 20% margin
        let spanLon = (maxLon - minLon) * 1.2  // Add 20% margin

        // Adjust centerLon if it crosses the International Date Line
        if containsAlaska && (maxLon - minLon > 180) {
            centerLon = (centerLon + 180).truncatingRemainder(dividingBy: 360) - 180
        }

        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                                        span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon))
        print("Calculated region: \(region)")

        return isValidRegion(region) ? region : calculateBoundingRegionFallback(overlays: overlays, containsAlaska: containsAlaska)
    }

    func calculateBoundingRegionFallback(overlays: [MKOverlay], containsAlaska: Bool) -> MKCoordinateRegion {
        var minLat = CLLocationDegrees(90.0)
        var maxLat = CLLocationDegrees(-90.0)
        var minLon = CLLocationDegrees(180.0)
        var maxLon = CLLocationDegrees(-180.0)

        for overlay in overlays {
            if let polygon = overlay as? MKPolygon {
                let points = polygon.points()
                for i in 0..<polygon.pointCount {
                    let coord = points[i].coordinate
                    minLat = min(minLat, coord.latitude)
                    maxLat = max(maxLat, coord.latitude)
                    minLon = min(minLon, coord.longitude)
                    maxLon = max(maxLon, coord.longitude)
                }
            } else if let multiPolygon = overlay as? MKMultiPolygon {
                for polygon in multiPolygon.polygons {
                    let points = polygon.points()
                    for i in 0..<polygon.pointCount {
                        let coord = points[i].coordinate
                        minLat = min(minLat, coord.latitude)
                        maxLat = max(maxLat, coord.latitude)
                        minLon = min(minLon, coord.longitude)
                        maxLon = max(maxLon, coord.longitude)
                    }
                }
            }
        }

        if containsAlaska {
            maxLat = max(maxLat, 70)
            minLon = min(minLon, -180)
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) * 1.2  // Add 20% margin
        let spanLon = (maxLon - minLon) * 1.2  // Add 20% margin

        let fallbackRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                                                span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon))
        print("Fallback region: \(fallbackRegion)")
        return fallbackRegion
    }

    func isValidRegion(_ region: MKCoordinateRegion) -> Bool {
        // Check if the region is valid
        let maxSpan = MKCoordinateSpan(latitudeDelta: 90.0, longitudeDelta: 180.0)
        return region.span.latitudeDelta <= maxSpan.latitudeDelta && region.span.longitudeDelta <= maxSpan.longitudeDelta
    }

    func loadGeoJSONData() -> String? {
        guard let url = Bundle.main.url(forResource: "us_states", withExtension: "geojson") else {
            print("GeoJSON file not found")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Failed to load GeoJSON file: \(error)")
            return nil
        }
    }
}
