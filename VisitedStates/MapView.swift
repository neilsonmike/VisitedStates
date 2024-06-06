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
        mapView.isUserInteractionEnabled = false  // Disable user interaction for production
        mapView.isScrollEnabled = false  // Disable scrolling for production
        mapView.isZoomEnabled = false  // Disable zooming for production
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
                            allPolygons.append(transformPolygon(polygon, for: stateName))
                            print("Added polygon with \(polygon.pointCount) points for state: \(stateName)")
                        } else if let multiPolygon = geometry as? MKMultiPolygon {
                            allPolygons.append(contentsOf: transformMultiPolygon(multiPolygon, for: stateName))
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

    func transformPolygon(_ polygon: MKPolygon, for state: String) -> MKPolygon {
        if state == "Alaska" {
            return transformCoordinates(for: polygon, scaleLat: 0.5, scaleLon: 0.4, offset: CLLocationCoordinate2D(latitude: 47.0, longitude: -135.0))
        } else if state == "Hawaii" {
            return transformCoordinates(for: polygon, scaleLat: 1.0, scaleLon: 1.2, offset: CLLocationCoordinate2D(latitude: 80.0, longitude: -123.0))
        } else {
            return polygon
        }
    }

    func transformMultiPolygon(_ multiPolygon: MKMultiPolygon, for state: String) -> [MKPolygon] {
        if state == "Alaska" || state == "Hawaii" {
            return multiPolygon.polygons.map { transformPolygon($0, for: state) }
        } else {
            return multiPolygon.polygons
        }
    }

    func transformCoordinates(for polygon: MKPolygon, scaleLat: Double, scaleLon: Double, offset: CLLocationCoordinate2D) -> MKPolygon {
        let points = polygon.points()
        var transformedCoordinates = [CLLocationCoordinate2D]()

        for i in 0..<polygon.pointCount {
            var coord = points[i].coordinate
            coord.latitude = (coord.latitude - 64) * scaleLat + offset.latitude  // Centering transformation on Alaska's latitude
            coord.longitude = (coord.longitude + 150) * scaleLon + offset.longitude  // Centering transformation on Alaska's longitude
            transformedCoordinates.append(coord)
        }

        return MKPolygon(coordinates: transformedCoordinates, count: transformedCoordinates.count)
    }

    func calculateBoundingRegion(for overlays: [MKOverlay]) -> MKCoordinateRegion {
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

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) * 1.2  // Add 20% margin
        let spanLon = (maxLon - minLon) * 1.2  // Add 20% margin

        // Ensure the spans are within a valid range
        let finalSpanLat = min(spanLat, 90.0)
        let finalSpanLon = min(spanLon, 180.0)

        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                                        span: MKCoordinateSpan(latitudeDelta: finalSpanLat, longitudeDelta: finalSpanLon))
        print("Calculated region: \(region)")
        return region
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
