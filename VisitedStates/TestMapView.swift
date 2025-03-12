import SwiftUI
import MapKit

struct TestMapView: View {
    // A binding for the map's region. We start with a region that covers most of the contiguous US.
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
    )
    
    var body: some View {
        VStack(spacing: 0) {
            // The map view that allows panning and zooming.
            MapViewRepresentable(region: $region)
                .edgesIgnoringSafeArea(.all)
            
            // Buttons to capture the current region for Alaska or Hawaii.
            HStack {
                Button("Set Alaska") {
                    print("Alaska preset region: Center = (\(region.center.latitude), \(region.center.longitude)), Span = (\(region.span.latitudeDelta), \(region.span.longitudeDelta))")
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
                
                Button("Set Hawaii") {
                    print("Hawaii preset region: Center = (\(region.center.latitude), \(region.center.longitude)), Span = (\(region.span.latitudeDelta), \(region.span.longitudeDelta))")
                }
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
        }
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.region = region
        // Enable user interaction (pinch, pan, etc.)
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Update the map view's region when the binding changes.
        uiView.setRegion(region, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Update the binding when the map's region changes.
            parent.region = mapView.region
        }
    }
}

struct TestMapView_Previews: PreviewProvider {
    static var previews: some View {
        TestMapView()
    }
}
