import SwiftUI
import MapKit
import CoreLocation

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
    @State private var currentSpan: MKCoordinateSpan?
    @State private var userLocationHelper = UserLocationHelper()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

            // MARK: - Recenter button
            if appState.targetCoordinate != nil {
                Button {
                    guard let coord = appState.targetCoordinate else { return }
                    let span = currentSpan ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cameraPosition = .region(
                            MKCoordinateRegion(center: coord, span: span)
                        )
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
        .onAppear {
            userLocationHelper.requestLocation { coordinate in
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                    )
                }
            }
        }
        .onMapCameraChange { context in
            currentSpan = context.region.span
        }
        .onChange(of: appState.targetCoordinate) { _, newValue in
            guard let coord = newValue else { return }
            let span = currentSpan ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            if movementEngine?.isMoving == true {
                // During movement: keep the arrow centered without animation
                cameraPosition = .region(
                    MKCoordinateRegion(center: coord, span: span)
                )
            } else {
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(
                        MKCoordinateRegion(center: coord, span: span)
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

// MARK: - User Location Helper

/// Requests the user's current location via CLLocationManager, triggering the
/// system permission dialog if needed. Calls back once with the coordinate.
@MainActor
private class UserLocationHelper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D) -> Void)?

    func requestLocation(completion: @escaping (CLLocationCoordinate2D) -> Void) {
        self.completion = completion
        manager.delegate = self

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            manager.requestLocation()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            completion?(location.coordinate)
            completion = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location unavailable — keep the default map position
    }
}
