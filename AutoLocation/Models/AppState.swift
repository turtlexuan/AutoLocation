import SwiftUI
import MapKit

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

@Observable
class AppState {
    var devices: [Device] = []
    var selectedDeviceUDID: String? = nil
    var targetCoordinate: CLLocationCoordinate2D? = nil
    var isSimulating: Bool = false
    var isPlayingGPX: Bool = false
    var statusMessage: String = "Ready"
    var isLoading: Bool = false
    var isBridgeReady: Bool = false
    var tunnelCommand: String? = nil  // Command to show user for starting tunnel

    var isMovementActive: Bool = false

    // Route planner
    var routeWaypoints: [Waypoint] = []
    var isEditingRoute: Bool = false
    var isFollowingRoute: Bool = false
    var currentRouteWaypointIndex: Int = 0
    var shouldLoopRoute: Bool = false

    var selectedDevice: Device? {
        devices.first { $0.udid == selectedDeviceUDID }
    }

    var coordinateText: String {
        guard let coord = targetCoordinate else { return "No location selected" }
        return String(format: "%.6f, %.6f", coord.latitude, coord.longitude)
    }
}
