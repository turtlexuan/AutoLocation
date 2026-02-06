import SwiftUI
import MapKit

struct MapContainerView: View {
    var appState: AppState
    var deviceManager: DeviceManager?
    var movementEngine: MovementEngine?

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let coord = appState.targetCoordinate {
                    if let engine = movementEngine, engine.isMoving {
                        // Heading indicator during movement
                        Annotation("", coordinate: coord) {
                            Image(systemName: "location.north.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .rotationEffect(.degrees(engine.currentBearing))
                                .shadow(color: .blue.opacity(0.5), radius: 3)
                        }
                    } else {
                        Marker("Target", coordinate: coord)
                            .tint(.red)
                    }
                }

                // Walk-to destination marker
                if let dest = movementEngine?.walkToDestination {
                    Marker("Destination", coordinate: dest)
                        .tint(.green)
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
            // Only animate camera when not actively moving (avoid constant re-centering)
            if movementEngine?.isMoving != true {
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
}
