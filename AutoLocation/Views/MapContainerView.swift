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
                // MARK: - Current location / target marker
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

                // MARK: - Route waypoint markers
                ForEach(Array(appState.routeWaypoints.enumerated()), id: \.element.id) { index, waypoint in
                    Annotation(
                        waypoint.name ?? "Waypoint \(index + 1)",
                        coordinate: waypoint.coordinate
                    ) {
                        ZStack {
                            Circle()
                                .fill(waypointColor(for: index))
                                .frame(width: 28, height: 28)
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .shadow(color: waypointColor(for: index).opacity(0.5), radius: 3)
                    }
                }

                // MARK: - Route polyline
                if appState.routeWaypoints.count >= 2 {
                    MapPolyline(
                        coordinates: appState.routeWaypoints.map(\.coordinate)
                    )
                    .stroke(.indigo, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                // MARK: - Active route segment highlight
                if appState.isFollowingRoute,
                   appState.currentRouteWaypointIndex < appState.routeWaypoints.count,
                   let currentLocation = appState.targetCoordinate {
                    MapPolyline(
                        coordinates: [
                            currentLocation,
                            appState.routeWaypoints[appState.currentRouteWaypointIndex].coordinate
                        ]
                    )
                    .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [8, 6]))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    if appState.isEditingRoute {
                        // In route editing mode: add a waypoint
                        let waypoint = Waypoint(coordinate: coordinate)
                        appState.routeWaypoints.append(waypoint)
                    } else {
                        // Normal mode: set target coordinate
                        appState.targetCoordinate = coordinate
                    }
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

    // MARK: - Helpers

    /// Returns the appropriate color for a waypoint based on route progress.
    /// - Green: already visited (index < currentRouteWaypointIndex)
    /// - Orange: current target waypoint (index == currentRouteWaypointIndex) while following
    /// - Blue: upcoming or when not following a route
    private func waypointColor(for index: Int) -> Color {
        guard appState.isFollowingRoute else { return .blue }

        if index < appState.currentRouteWaypointIndex {
            return .green
        } else if index == appState.currentRouteWaypointIndex {
            return .orange
        } else {
            return .blue
        }
    }
}
