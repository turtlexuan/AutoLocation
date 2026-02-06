import SwiftUI
import MapKit

struct MapContainerView: View {
    var appState: AppState
    var deviceManager: DeviceManager?

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let coord = appState.targetCoordinate {
                    Marker("Target", coordinate: coord)
                        .tint(.red)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    appState.targetCoordinate = coordinate
                }
            }
        }
        .onChange(of: appState.targetCoordinate) { _, newValue in
            guard let coord = newValue else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                )
            }
        }
    }
}
