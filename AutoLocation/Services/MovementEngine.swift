import Foundation
import MapKit

@Observable
@MainActor
class MovementEngine {
    // MARK: - Published State

    private(set) var currentLocation: CLLocationCoordinate2D?
    private(set) var currentBearing: Double = 0    // degrees, 0 = north
    private(set) var currentSpeed: Double = 0      // m/s
    private(set) var isMoving: Bool = false
    private(set) var distanceTraveled: Double = 0  // meters
    var speedMode: SpeedMode = .walk

    // Walk-to-point state
    private(set) var walkToDestination: CLLocationCoordinate2D?
    private(set) var isWalkingToPoint: Bool = false

    // Route-following state
    private var routeWaypoints: [Waypoint] = []

    // MARK: - Speed Modes

    enum SpeedMode: String, CaseIterable, Identifiable {
        case walk = "Walk"
        case run = "Run"
        case cycle = "Cycle"
        case drive = "Drive"

        var id: String { rawValue }

        var maxSpeed: Double {
            switch self {
            case .walk:  return 1.4
            case .run:   return 3.0
            case .cycle: return 5.5
            case .drive: return 11.0
            }
        }

        var icon: String {
            switch self {
            case .walk:  return "figure.walk"
            case .run:   return "figure.run"
            case .cycle: return "figure.outdoor.cycle"
            case .drive: return "car"
            }
        }
    }

    // MARK: - Private State

    private var inputBearing: Double = 0
    private var inputMagnitude: Double = 0   // 0.0 – 1.0
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 1.0

    private var appState: AppState
    private weak var deviceManager: DeviceManager?

    // MARK: - Init

    init(appState: AppState, deviceManager: DeviceManager?) {
        self.appState = appState
        self.deviceManager = deviceManager
    }

    // MARK: - Input from Joystick / Keyboard

    func updateInput(bearing: Double, magnitude: Double) {
        inputBearing = bearing
        inputMagnitude = min(max(magnitude, 0), 1)

        if magnitude > 0 {
            currentBearing = bearing
            currentSpeed = speedMode.maxSpeed * inputMagnitude

            // Cancel walk-to-point and route if user takes manual control
            if isWalkingToPoint {
                isWalkingToPoint = false
                walkToDestination = nil
            }
            if appState.isFollowingRoute {
                routeWaypoints = []
                appState.isFollowingRoute = false
                appState.currentRouteWaypointIndex = 0
                appState.statusMessage = "Route cancelled (manual control)"
            }

            if !isMoving {
                startMoving()
            }
        } else {
            currentSpeed = 0
            if !isWalkingToPoint {
                stopMoving()
            }
        }
    }

    // MARK: - Walk to Point

    func walkToPoint(_ destination: CLLocationCoordinate2D) {
        guard let current = currentLocation ?? appState.targetCoordinate else { return }

        walkToDestination = destination
        isWalkingToPoint = true
        currentSpeed = speedMode.maxSpeed
        currentBearing = Self.bearing(from: current, to: destination)

        if currentLocation == nil {
            currentLocation = current
        }

        if !isMoving {
            startMoving()
        }
    }

    func cancelWalkToPoint() {
        isWalkingToPoint = false
        walkToDestination = nil
        currentSpeed = 0
        stopMoving()
    }

    // MARK: - Route Following

    func followRoute(waypoints: [Waypoint]) {
        guard !waypoints.isEmpty else { return }

        routeWaypoints = waypoints
        appState.isFollowingRoute = true
        appState.currentRouteWaypointIndex = 0

        // Navigate to the first waypoint using the existing walk-to logic
        walkToPoint(waypoints[0].coordinate)
    }

    func stopRoute() {
        routeWaypoints = []
        appState.isFollowingRoute = false
        appState.currentRouteWaypointIndex = 0
        stopMoving()
    }

    private func advanceToNextWaypoint() {
        let nextIndex = appState.currentRouteWaypointIndex + 1

        if nextIndex < routeWaypoints.count {
            // More waypoints remain
            appState.currentRouteWaypointIndex = nextIndex
            walkToPoint(routeWaypoints[nextIndex].coordinate)
        } else if appState.shouldLoopRoute {
            // Route complete, loop back to start
            appState.currentRouteWaypointIndex = 0
            walkToPoint(routeWaypoints[0].coordinate)
        } else {
            // Route complete, no loop
            appState.isFollowingRoute = false
            routeWaypoints = []
            appState.currentRouteWaypointIndex = 0
            appState.statusMessage = "Route complete"
        }
    }

    // MARK: - Movement Control

    func startMoving() {
        guard updateTimer == nil else { return }

        // Initialize current location from pin if not set
        if currentLocation == nil {
            currentLocation = appState.targetCoordinate
        }
        guard currentLocation != nil else { return }

        isMoving = true
        appState.isSimulating = true

        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func stopMoving() {
        updateTimer?.invalidate()
        updateTimer = nil
        isMoving = false
        currentSpeed = 0
        isWalkingToPoint = false
        walkToDestination = nil
    }

    func resetDistance() {
        distanceTraveled = 0
    }

    // MARK: - Timer Tick

    private func tick() {
        guard let location = currentLocation, currentSpeed > 0 else { return }

        // Walk-to-point: update bearing toward destination and check arrival
        if isWalkingToPoint, let dest = walkToDestination {
            let remainingDistance = Self.distance(from: location, to: dest)
            let stepDistance = currentSpeed * updateInterval

            if remainingDistance <= stepDistance {
                // Arrived at destination
                currentLocation = dest
                appState.targetCoordinate = dest
                distanceTraveled += remainingDistance
                sendLocationUpdate(dest)

                if appState.isFollowingRoute {
                    // Clear current walk-to state before advancing
                    isWalkingToPoint = false
                    walkToDestination = nil

                    let waypointName = routeWaypoints[safe: appState.currentRouteWaypointIndex]?.name
                        ?? "Waypoint \(appState.currentRouteWaypointIndex + 1)"
                    appState.statusMessage = "Reached \(waypointName)"

                    advanceToNextWaypoint()
                } else {
                    cancelWalkToPoint()
                    appState.statusMessage = "Arrived at destination"
                }
                return
            }

            // Update bearing toward destination
            currentBearing = Self.bearing(from: location, to: dest)
            currentSpeed = speedMode.maxSpeed
        }

        let distance = currentSpeed * updateInterval
        let newLocation = Self.destinationPoint(from: location, distance: distance, bearing: currentBearing)

        currentLocation = newLocation
        appState.targetCoordinate = newLocation
        distanceTraveled += distance

        sendLocationUpdate(newLocation)
    }

    private func sendLocationUpdate(_ coord: CLLocationCoordinate2D) {
        Task {
            await deviceManager?.setLocationSilent(
                latitude: coord.latitude,
                longitude: coord.longitude
            )
        }
    }

    // MARK: - Coordinate Math

    static func destinationPoint(
        from start: CLLocationCoordinate2D,
        distance: Double,
        bearing: Double
    ) -> CLLocationCoordinate2D {
        let bearingRad = bearing * .pi / 180.0
        let dy = distance * cos(bearingRad)
        let dx = distance * sin(bearingRad)

        let newLat = start.latitude + (dy / 111_139.0)
        let newLon = start.longitude + (dx / (111_320.0 * cos(start.latitude * .pi / 180.0)))

        return CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }

    static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = start.latitude * .pi / 180.0
        let lat2 = end.latitude * .pi / 180.0
        let dLon = (end.longitude - start.longitude) * .pi / 180.0

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let theta = atan2(y, x)

        return (theta * 180.0 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func distance(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let dLat = (end.latitude - start.latitude) * .pi / 180.0
        let dLon = (end.longitude - start.longitude) * .pi / 180.0
        let lat1 = start.latitude * .pi / 180.0
        let lat2 = end.latitude * .pi / 180.0

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return 6_371_000.0 * c
    }

    // MARK: - Helpers

    static func compassDirection(for bearing: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((bearing + 22.5).truncatingRemainder(dividingBy: 360)) / 45.0)
        return directions[index]
    }

    var bearingText: String {
        let dir = Self.compassDirection(for: currentBearing)
        return String(format: "%03.0f° %@", currentBearing, dir)
    }

    var speedText: String {
        if currentSpeed < 1.0 {
            return String(format: "%.1f m/s", currentSpeed)
        } else {
            return String(format: "%.1f km/h", currentSpeed * 3.6)
        }
    }

    var distanceText: String {
        if distanceTraveled < 1000 {
            return String(format: "%.0f m", distanceTraveled)
        } else {
            return String(format: "%.2f km", distanceTraveled / 1000)
        }
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
