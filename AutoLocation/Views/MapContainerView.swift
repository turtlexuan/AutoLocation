import SwiftUI
import MapKit

struct MapContainerView: View {
    var appState: AppState
    var deviceManager: DeviceManager?
    var movementEngine: MovementEngine?

    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: defaultCenter, span: defaultSpan)
    )
    @State private var currentSpan: MKCoordinateSpan?
    @State private var userLocationHelper = UserLocationHelper()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    targetMarker
                    destinationMarker
                    waypointMarkers
                    routePolyline
                    activeRouteSegment
                }
                .mapStyle(.standard(elevation: .realistic))
                .onTapGesture { screenPoint in
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    handleMapTap(at: coordinate)
                }
            }

            recenterButton
        }
        .onAppear {
            userLocationHelper.requestLocation { coordinate in
                updateCamera(to: coordinate, animated: true)
            }
        }
        .onMapCameraChange { context in
            currentSpan = context.region.span
        }
        .onChange(of: appState.targetCoordinate) { _, newValue in
            guard let coord = newValue else { return }
            let isMoving = movementEngine?.isMoving == true
            updateCamera(to: coord, animated: !isMoving)
        }
    }

    // MARK: - Map Content

    @MapContentBuilder
    private var targetMarker: some MapContent {
        if let coord = appState.targetCoordinate {
            if let engine = movementEngine, engine.isMoving {
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
    }

    @MapContentBuilder
    private var destinationMarker: some MapContent {
        if let dest = movementEngine?.walkToDestination {
            Marker("Destination", coordinate: dest)
                .tint(.green)
        }
    }

    @MapContentBuilder
    private var waypointMarkers: some MapContent {
        ForEach(Array(appState.routeWaypoints.enumerated()), id: \.element.id) { index, waypoint in
            Annotation(
                waypoint.name ?? "Waypoint \(index + 1)",
                coordinate: waypoint.coordinate
            ) {
                waypointBadge(index: index)
            }
        }
    }

    @MapContentBuilder
    private var routePolyline: some MapContent {
        if appState.routeWaypoints.count >= 2 {
            MapPolyline(coordinates: appState.routeWaypoints.map(\.coordinate))
                .stroke(.indigo, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }

    @MapContentBuilder
    private var activeRouteSegment: some MapContent {
        if appState.isFollowingRoute,
           appState.currentRouteWaypointIndex < appState.routeWaypoints.count,
           let currentLocation = appState.targetCoordinate {
            MapPolyline(coordinates: [
                currentLocation,
                appState.routeWaypoints[appState.currentRouteWaypointIndex].coordinate
            ])
            .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [8, 6]))
        }
    }

    // MARK: - Subviews

    private func waypointBadge(index: Int) -> some View {
        let color = waypointColor(for: index)
        return ZStack {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: 28, height: 28)
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .shadow(color: color.opacity(0.5), radius: 3)
    }

    @ViewBuilder
    private var recenterButton: some View {
        if appState.targetCoordinate != nil {
            Button {
                guard let coord = appState.targetCoordinate else { return }
                updateCamera(to: coord, animated: true)
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

    // MARK: - Helpers

    private func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        if appState.isEditingRoute {
            appState.routeWaypoints.append(Waypoint(coordinate: coordinate))
        } else {
            appState.targetCoordinate = coordinate
        }
    }

    private func updateCamera(to center: CLLocationCoordinate2D, animated: Bool) {
        let span = currentSpan ?? Self.defaultSpan
        let region = MKCoordinateRegion(center: center, span: span)
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }

    /// Returns the color for a waypoint based on route progress:
    /// green = visited, orange = current target, blue = upcoming.
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
