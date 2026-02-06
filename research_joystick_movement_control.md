# Deep Research: Real-Time Movement / Joystick Control for iOS Location Simulation

## Table of Contents

1. [DVT LocationSimulation Update Frequency & Rate Limits](#1-dvt-update-frequency)
2. [Realistic GPS Movement Simulation](#2-realistic-gps-movement)
3. [Joystick UI Patterns in SwiftUI](#3-joystick-ui-patterns)
4. [Movement Modes & Features](#4-movement-modes)
5. [Technical Architecture](#5-technical-architecture)
6. [Existing Implementations & References](#6-existing-implementations)
7. [Potential Issues & Anti-Spoofing](#7-potential-issues)
8. [Practical Recommendations for AutoLocation](#8-recommendations)

---

## 1. DVT LocationSimulation Update Frequency & Rate Limits <a name="1-dvt-update-frequency"></a>

### How the DVT LocationSimulation Channel Works

From the pymobiledevice3 source code (installed in our project's venv), the `LocationSimulation` class operates as follows:

```python
# pymobiledevice3/services/dvt/instruments/location_simulation.py
class LocationSimulation(LocationSimulationBase):
    IDENTIFIER = "com.apple.instruments.server.services.LocationSimulation"

    def __init__(self, dvt):
        self._channel = dvt.make_channel(self.IDENTIFIER)

    def set(self, latitude: float, longitude: float) -> None:
        self._channel.simulateLocationWithLatitude_longitude_(
            MessageAux().append_obj(latitude).append_obj(longitude)
        )
        self._channel.receive_plist()  # Waits for acknowledgment

    def clear(self) -> None:
        self._channel.stopLocationSimulation()
```

**Key observations:**

1. **Each `set()` call sends a DTX message and waits for a plist response** -- this is a synchronous request-response cycle. The `receive_plist()` call blocks until the device acknowledges the location update.

2. **The DVT channel is persistent** -- once created via `dvt.make_channel()`, it remains open. Multiple `set()` calls reuse the same channel without reconnection overhead.

3. **No explicit rate limit in the code** -- pymobiledevice3 does not impose any throttle or minimum interval between calls.

### Empirical Rate Limit Findings

Based on pymobiledevice3 GitHub issues and community discussions:

- **Issue #767**: The DVT simulate-location process must stay alive for the simulation to persist. Closing the process (or the DVT channel) ends the simulation. This confirms the channel is designed for persistent/continuous use.

- **Issue #572**: Reports of unreliable location clearing on iOS 17, but no reports of errors from rapid `set()` calls. The issues are about the `clear()` operation, not `set()` frequency.

- **Issue #340**: Request for speed/heading/altitude support. The maintainer confirmed "DTSimulateLocation only supports setting longitude and latitude parameters." Apple's API is limited to lat/lon only.

- **GPX playback in pymobiledevice3**: The built-in `play_gpx_file()` method calls `set()` sequentially with delays based on GPX timestamps. When `disable_sleep=True` is used, it calls `set()` as fast as possible with no artificial delay. No errors are reported from this rapid-fire usage.

### Estimated Practical Update Rate

| Factor | Details |
|--------|---------|
| **Network overhead** | Each `set()` requires a DTX message send + plist response receive |
| **USB latency** | Typically 1-5ms round-trip for USB, 10-50ms for WiFi tunnel |
| **DVT processing** | iOS must process the DTX message and update `locationd` |
| **No hard rate limit** | No documented maximum frequency from Apple |
| **Practical maximum** | ~10-20 updates/sec over USB, ~5-10 over WiFi (estimated) |
| **Recommended rate** | 1-4 updates/sec for realistic movement simulation |

### Why 1-4 Updates/Sec is Optimal

- **Real GPS hardware** typically updates at 1 Hz (once per second). Some high-end devices do 5 Hz or 10 Hz.
- **CoreLocation on iOS** typically delivers updates at ~1-2 Hz in the foreground.
- **Matching real GPS behavior** means 1 Hz is the most natural rate.
- **2-4 Hz** provides smoother visual updates without appearing unnatural.
- **Higher rates** waste bandwidth and may trigger suspicion in anti-spoofing systems expecting ~1 Hz GPS data.

### How Our Bridge Already Handles This

Our existing `bridge.py` already keeps the DVT session persistent:

```python
# bridge.py - persistent DVT session management
_dvt_sessions: dict = {}  # udid -> {"dvt": ..., "loc_sim": ...}

def _get_dvt_session(rsd, udid):
    if udid in _dvt_sessions:
        return _dvt_sessions[udid]["loc_sim"]
    dvt = DvtSecureSocketProxyService(lockdown=rsd)
    dvt.__enter__()
    loc_sim = LocationSimulation(dvt)
    _dvt_sessions[udid] = {"dvt": dvt, "loc_sim": loc_sim}
    return loc_sim
```

This means repeated `set_location` commands from Swift reuse the same DVT channel -- no reconnection overhead. The bridge is already architecturally ready for continuous updates.

---

## 2. Realistic GPS Movement Simulation <a name="2-realistic-gps-movement"></a>

### Movement Speed Reference Table

| Mode | Speed (m/s) | Speed (km/h) | Speed (mph) | Notes |
|------|------------|-------------|------------|-------|
| Slow walk | 0.8-1.0 | 2.9-3.6 | 1.8-2.2 | Elderly, browsing shops |
| Normal walk | 1.2-1.4 | 4.3-5.0 | 2.7-3.1 | Standard pedestrian pace |
| Brisk walk | 1.5-2.0 | 5.4-7.2 | 3.4-4.5 | Exercise walking |
| Jogging | 2.0-3.0 | 7.2-10.8 | 4.5-6.7 | Light running |
| Running | 3.0-5.0 | 10.8-18.0 | 6.7-11.2 | Athletic running |
| Cycling | 4.0-8.0 | 14.4-28.8 | 9.0-17.9 | Casual to moderate |
| Urban driving | 8.0-14.0 | 28.8-50.4 | 17.9-31.3 | City streets |
| Highway driving | 25.0-35.0 | 90.0-126.0 | 55.9-78.3 | Freeway |

**Recommended default speeds for the app:**

| Mode | Speed (m/s) | Rationale |
|------|------------|-----------|
| Walk | 1.4 | Standard human walking speed per design guides |
| Run | 3.0 | Moderate jogging pace |
| Cycle | 5.5 | Average casual cycling |
| Drive | 11.0 | Urban speed (~40 km/h) |

### Coordinate Math: Moving a Point

**The destination point formula** (given starting lat/lon, distance in meters, and bearing in degrees):

```
phi2 = asin( sin(phi1) * cos(d/R) + cos(phi1) * sin(d/R) * cos(theta) )
lambda2 = lambda1 + atan2( sin(theta) * sin(d/R) * cos(phi1),
                            cos(d/R) - sin(phi1) * sin(phi2) )
```

Where:
- `phi1`, `lambda1` = starting latitude/longitude in **radians**
- `theta` = bearing in **radians** (clockwise from north, 0 = north, 90 = east)
- `d` = distance in meters
- `R` = Earth's radius (~6,371,000 meters)

**Simplified approximation** (accurate for small distances, <1km):

```swift
// Approximate meters-per-degree conversions
let metersPerDegreeLat = 111_139.0  // roughly constant
let metersPerDegreeLon = 111_320.0 * cos(latitude * .pi / 180.0)  // varies with latitude

// Move by dx meters east and dy meters north
let newLat = lat + (dy / metersPerDegreeLat)
let newLon = lon + (dx / metersPerDegreeLon)
```

**For bearing-based movement:**

```swift
// Given bearing (degrees, 0=north, 90=east) and distance (meters)
let dx = distance * sin(bearing * .pi / 180.0)  // eastward component
let dy = distance * cos(bearing * .pi / 180.0)  // northward component

let newLat = lat + (dy / 111_139.0)
let newLon = lon + (dx / (111_320.0 * cos(lat * .pi / 180.0)))
```

**Exact formula (Swift):**

```swift
func destinationPoint(from start: CLLocationCoordinate2D,
                      distance: Double,
                      bearing: Double) -> CLLocationCoordinate2D {
    let R = 6_371_000.0  // Earth radius in meters
    let phi1 = start.latitude * .pi / 180.0
    let lambda1 = start.longitude * .pi / 180.0
    let theta = bearing * .pi / 180.0
    let delta = distance / R  // angular distance

    let phi2 = asin(sin(phi1) * cos(delta) + cos(phi1) * sin(delta) * cos(theta))
    let lambda2 = lambda1 + atan2(sin(theta) * sin(delta) * cos(phi1),
                                   cos(delta) - sin(phi1) * sin(phi2))

    return CLLocationCoordinate2D(
        latitude: phi2 * 180.0 / .pi,
        longitude: lambda2 * 180.0 / .pi
    )
}
```

### Making Movement Look Natural

**Characteristics of real GPS data:**

1. **GPS jitter**: Real GPS has ~2-5 meter accuracy noise. Even a stationary device shows position fluctuations.
2. **Speed variation**: Humans don't walk at perfectly constant speed. Walking speed varies by +/- 10-15%.
3. **Path curvature**: People don't walk in perfectly straight lines; they follow roads and make gradual turns.
4. **Acceleration/deceleration**: Starting and stopping are gradual, not instant.
5. **Heading changes**: Turns happen over multiple seconds, not instantaneously.

**Practical naturalism techniques:**

```swift
// Add GPS-like jitter (random noise within ~2-5m)
let jitterLat = Double.random(in: -0.00003...0.00003)  // ~3m
let jitterLon = Double.random(in: -0.00003...0.00003)

// Speed variation (+/- 10%)
let speedFactor = 1.0 + Double.random(in: -0.10...0.10)
let effectiveSpeed = baseSpeed * speedFactor

// Smooth acceleration (ramp up/down over ~2-3 seconds)
let maxAcceleration = 0.5  // m/s^2 for walking
currentSpeed = min(targetSpeed, currentSpeed + maxAcceleration * deltaTime)
```

**Note on diminishing returns**: For most use cases (testing apps, general location spoofing), simple constant-speed movement along a bearing is sufficient. Full naturalism with jitter and acceleration is only needed to evade aggressive anti-spoofing systems.

---

## 3. Joystick UI Patterns in SwiftUI <a name="3-joystick-ui-patterns"></a>

### Approach 1: DragGesture-Based Virtual Joystick

This is the most intuitive control for a macOS app. The user drags a thumb within a circular area.

**Core implementation pattern:**

```swift
struct JoystickView: View {
    @State private var dragOffset: CGSize = .zero
    let radius: CGFloat = 60
    var onUpdate: (CGFloat, CGFloat) -> Void  // (angle in degrees, magnitude 0-1)

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)

            // Thumb
            Circle()
                .fill(Color.accentColor)
                .frame(width: 30, height: 30)
                .offset(dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let translation = value.translation
                            let distance = sqrt(translation.width * translation.width +
                                                translation.height * translation.height)
                            let clampedDistance = min(distance, radius)

                            // Clamp to circle
                            if distance > 0 {
                                let scale = clampedDistance / distance
                                dragOffset = CGSize(
                                    width: translation.width * scale,
                                    height: translation.height * scale
                                )
                            }

                            // Calculate angle (0 = north, clockwise)
                            let angle = atan2(translation.width, -translation.height) * 180 / .pi
                            let normalizedAngle = angle < 0 ? angle + 360 : angle
                            let magnitude = clampedDistance / radius  // 0.0 to 1.0

                            onUpdate(normalizedAngle, magnitude)
                        }
                        .onEnded { _ in
                            dragOffset = .zero
                            onUpdate(0, 0)  // Signal stop
                        }
                )
        }
        .frame(width: radius * 2 + 40, height: radius * 2 + 40)
    }
}
```

**Mapping joystick to movement:**

```swift
// angle: 0 = north, 90 = east, 180 = south, 270 = west
// magnitude: 0.0 (center/stopped) to 1.0 (full displacement)

let bearing = joystickAngle  // degrees, maps directly to compass bearing
let speedMultiplier = joystickMagnitude  // 0-1
let effectiveSpeed = baseSpeed * speedMultiplier  // m/s
```

### Approach 2: Keyboard Controls (WASD / Arrow Keys)

SwiftUI provides `.onKeyPress()` for handling keyboard input.

**Implementation pattern:**

```swift
struct MovementView: View {
    @State private var activeDirections: Set<Direction> = []
    @FocusState private var isFocused: Bool

    enum Direction { case north, south, east, west }

    var body: some View {
        content
            .focusable()
            .focused($isFocused)
            .onKeyPress(phases: .down) { press in
                if let dir = direction(for: press) {
                    activeDirections.insert(dir)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(phases: .up) { press in
                if let dir = direction(for: press) {
                    activeDirections.remove(dir)
                    return .handled
                }
                return .ignored
            }
            .onAppear { isFocused = true }
    }

    func direction(for press: KeyPress) -> Direction? {
        switch press.key {
        case .upArrow, KeyEquivalent("w"): return .north
        case .downArrow, KeyEquivalent("s"): return .south
        case .leftArrow, KeyEquivalent("a"): return .west
        case .rightArrow, KeyEquivalent("d"): return .east
        default: return nil
        }
    }

    // Combine active directions into a bearing
    var currentBearing: Double? {
        guard !activeDirections.isEmpty else { return nil }
        var dx: Double = 0
        var dy: Double = 0
        if activeDirections.contains(.north) { dy += 1 }
        if activeDirections.contains(.south) { dy -= 1 }
        if activeDirections.contains(.east) { dx += 1 }
        if activeDirections.contains(.west) { dx -= 1 }
        if dx == 0 && dy == 0 { return nil }
        let angle = atan2(dx, dy) * 180 / .pi
        return angle < 0 ? angle + 360 : angle
    }
}
```

**Important notes for macOS SwiftUI keyboard handling:**

- The view MUST have `.focusable()` applied before `.onKeyPress()`
- Use `@FocusState` to ensure the view has keyboard focus
- `.onKeyPress(phases: .down)` fires on initial press
- `.onKeyPress(phases: .repeat)` fires continuously while held (auto-repeat)
- `.onKeyPress(phases: .up)` fires on release
- The `characters` property does NOT include modifier keys
- For arrow keys, use `KeyEquivalent.upArrow`, `.downArrow`, etc.
- Must normalize to lowercase to handle shift-key edge cases

### Approach 3: Click-to-Walk on Map

The user clicks a destination on the map, and the simulated location "walks" there in a straight line.

```swift
// On map tap/click:
let destination = clickedCoordinate
let startPoint = currentSimulatedLocation
let totalDistance = haversineDistance(from: startPoint, to: destination)
let bearing = initialBearing(from: startPoint, to: destination)
let duration = totalDistance / walkingSpeed  // seconds

// Start a timer that moves along the bearing
movementTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
    let stepDistance = walkingSpeed * updateInterval
    currentLocation = destinationPoint(from: currentLocation,
                                        distance: stepDistance,
                                        bearing: bearing)
    sendLocationUpdate(currentLocation)

    if haversineDistance(from: currentLocation, to: destination) < stepDistance {
        // Arrived
        movementTimer?.invalidate()
        sendLocationUpdate(destination)
    }
}
```

### Approach 4: Existing Library -- SwiftUIJoystick

The [SwiftUIJoystick](https://github.com/michael94ellis/SwiftUIJoystick) library provides a ready-made joystick:

```swift
// SPM: https://github.com/michael94ellis/SwiftUIJoystick

@StateObject private var monitor = JoystickMonitor(width: 100)

JoystickBuilder(
    monitor: monitor,
    width: 100,
    shape: .circle,
    background: { Circle().fill(Color.gray.opacity(0.2)) },
    foreground: { Circle().fill(Color.blue) },
    locksInPlace: false
)

// Read values:
// monitor.xyPoint -- CGPoint with x,y displacement
// Convert to polar: angle = atan2(x - center, -(y - center))
```

**Recommendation**: Building a custom joystick (Approach 1) gives more control and avoids a dependency. The code is straightforward (~50 lines) and can be tailored exactly to our needs.

---

## 4. Movement Modes & Features <a name="4-movement-modes"></a>

### Movement Modes to Implement

**Priority 1 (Essential):**

1. **Free walk with joystick** -- Drag joystick to set direction; magnitude controls speed within the selected mode's range. Releasing the joystick stops movement.

2. **Speed mode selector** -- Toggle between Walk (1.4 m/s), Run (3.0 m/s), Cycle (5.5 m/s), Drive (11.0 m/s). The joystick magnitude scales within the selected mode.

3. **WASD / Arrow key controls** -- Keyboard alternative to joystick. Hold W/Up to go north, etc. Diagonal movement supported (W+D = northeast).

**Priority 2 (Useful):**

4. **Walk to point** -- Click on map to set destination. Auto-walk in a straight line at selected speed. Show progress on map.

5. **Heading display** -- Show current bearing/heading as a compass direction (N, NE, E, etc.) and as degrees.

6. **Current speed display** -- Show the effective speed in m/s or km/h.

**Priority 3 (Nice to have):**

7. **Route following** -- Load a GPX or draw waypoints on the map; auto-walk through them sequentially.

8. **Speed slider** -- Fine-grained speed control (0.5 - 30 m/s continuous slider).

9. **GPS jitter toggle** -- Add random noise to simulate real GPS inaccuracy.

10. **Acceleration/deceleration** -- Smooth start/stop instead of instant speed changes.

### UI Layout Concept

```
+------------------------------------------+
|  Map (full width)                         |
|                                           |
|                      [heading indicator]  |
|                                           |
|  [speed: 1.4 m/s]   [mode: Walk]        |
+------------------------------------------+
|  Control Panel (bottom or sidebar)        |
|                                           |
|  [Joystick]    [Speed Mode Buttons]       |
|                Walk | Run | Cycle | Drive  |
|                                           |
|  [Bearing: 045 NE]  [Distance: 142m]     |
+------------------------------------------+
```

---

## 5. Technical Architecture <a name="5-technical-architecture"></a>

### Movement Simulation Loop

The core architecture is a timer-driven update loop that:
1. Reads input state (joystick displacement / keyboard direction)
2. Calculates new position based on bearing + speed + elapsed time
3. Sends the new position to the Python bridge
4. Updates the UI (map marker, stats display)

**Recommended update frequency: 1 Hz (1 update per second)**

Rationale:
- Matches real GPS hardware update rate
- Minimizes DVT channel overhead
- Looks natural to apps consuming CoreLocation data
- Easy math: distance per update = speed in m/s

For smoother UI, the map marker can interpolate between updates at 30-60 fps visually, while actual DVT updates go out at 1 Hz.

### Timer Architecture (Swift)

```swift
@Observable
class MovementEngine {
    var currentLocation: CLLocationCoordinate2D
    var currentBearing: Double = 0       // degrees
    var currentSpeed: Double = 0         // m/s
    var isMoving: Bool = false
    var speedMode: SpeedMode = .walk

    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 1.0  // 1 Hz

    enum SpeedMode: String, CaseIterable {
        case walk = "Walk"
        case run = "Run"
        case cycle = "Cycle"
        case drive = "Drive"

        var maxSpeed: Double {
            switch self {
            case .walk: return 1.4
            case .run: return 3.0
            case .cycle: return 5.5
            case .drive: return 11.0
            }
        }
    }

    func startMoving() {
        guard updateTimer == nil else { return }
        isMoving = true
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval,
                                            repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopMoving() {
        updateTimer?.invalidate()
        updateTimer = nil
        isMoving = false
        currentSpeed = 0
    }

    private func tick() {
        guard currentSpeed > 0 else { return }

        let distance = currentSpeed * updateInterval  // meters to move
        let newLocation = destinationPoint(from: currentLocation,
                                            distance: distance,
                                            bearing: currentBearing)
        currentLocation = newLocation

        // Send to bridge asynchronously
        Task {
            await deviceManager.setLocation(
                latitude: newLocation.latitude,
                longitude: newLocation.longitude
            )
        }
    }

    // Called by joystick/keyboard input
    func updateInput(bearing: Double, magnitude: Double) {
        currentBearing = bearing
        currentSpeed = speedMode.maxSpeed * magnitude

        if magnitude > 0 && !isMoving {
            startMoving()
        } else if magnitude == 0 {
            stopMoving()
        }
    }
}
```

### Thread Safety Considerations

The current `PythonBridge` is an `actor`, which already provides thread safety for the stdin/stdout communication. However, the movement loop creates a specific concern:

**Problem**: The Timer fires on the main thread, calls `deviceManager.setLocation()` which is `@MainActor`, and that calls `bridge.send()` which is on the `PythonBridge` actor. If the bridge is still processing the previous `set_location` when the next tick fires, the timer callback will await.

**Solution options:**

1. **Fire-and-forget** (recommended): Don't await the bridge response in the movement loop. Use `Task.detached` to send updates without blocking the timer.

```swift
private func tick() {
    guard currentSpeed > 0 else { return }
    let distance = currentSpeed * updateInterval
    let newLocation = destinationPoint(from: currentLocation,
                                        distance: distance,
                                        bearing: currentBearing)
    currentLocation = newLocation

    // Fire and forget - don't block the movement loop
    Task { @MainActor in
        await deviceManager.setLocationSilent(
            latitude: newLocation.latitude,
            longitude: newLocation.longitude
        )
    }
}
```

2. **Skip if busy**: Track whether a location update is in-flight; skip the tick if the previous one hasn't completed yet.

3. **Dedicated movement command**: Add a specialized `move` command to the Python bridge that accepts bearing + speed + duration, letting Python handle the timer loop. This moves the timing-critical code closer to the device.

### Bridge Protocol Extension

To support continuous movement, extend the bridge protocol:

```json
// New commands for movement control
{"command": "start_movement", "udid": "...", "latitude": 37.7749,
 "longitude": -122.4194, "bearing": 45.0, "speed": 1.4,
 "updateInterval": 1.0}

{"command": "update_movement", "udid": "...", "bearing": 90.0, "speed": 2.0}

{"command": "stop_movement", "udid": "..."}
```

**Alternative (simpler)**: Keep the existing `set_location` command and drive the timer from Swift. This is simpler and keeps the Python bridge stateless. The bridge just relays coordinates. This is the recommended approach for initial implementation.

### Optimizing the PythonBridge for Rapid Updates

The current `PythonBridge.send()` method is a strict request-response pattern -- it sends a command and awaits a response. For movement updates, we can optimize:

1. **Add a "fire-and-forget" send method** that doesn't wait for a response:

```swift
// In PythonBridge.swift
func sendFireAndForget(command: [String: Any]) async throws {
    guard isRunning, let stdinPipe = stdinPipe else {
        throw BridgeError.processNotRunning
    }
    let jsonData = try JSONSerialization.data(withJSONObject: command, options: [])
    guard var line = String(data: jsonData, encoding: .utf8) else {
        throw BridgeError.invalidResponse
    }
    line += "\n"
    if let data = line.data(using: .utf8) {
        stdinPipe.fileHandleForWriting.write(data)
    }
}
```

2. **Handle responses asynchronously** -- the bridge can still log errors to stderr, but the movement loop doesn't stall waiting for "ok".

---

## 6. Existing Implementations & References <a name="6-existing-implementations"></a>

### LocationSimulator (Schlaubischlump) -- Most Feature-Rich Reference

**Repository**: https://github.com/Schlaubischlump/LocationSimulator

This is the closest existing open-source implementation to what we want. Key features:

- **Movement controls**: Arrow keys to change direction and move, Space to stop
- **Speed modes**: Walk / Cycle / Drive (custom speeds also supported)
- **Direction indicator**: Blue triangle on map shows current heading, draggable to change direction
- **Auto-move**: Long-press the walk button to enable continuous movement
- **Navigation**: Click on map to auto-navigate to that point
- **Backend**: Uses `LocationSpoofer` Swift package which wraps libimobiledevice

**Architecture insights from LocationSpoofer:**

- `manual` mode: Developer calls `move()` to advance position
- `auto` mode: Internal timer calls `move()` periodically at configured speed
- `navigation(route)` mode: Follows a `NavigationRoute` through waypoints
- Speed is configurable as a `Double` property (m/s)
- Heading is configurable as `Double` (degrees)

**Limitation**: Built on libimobiledevice, not pymobiledevice3. iOS 17+ support is limited and depends on pre-mounting the DDI via Xcode.

### GeoPort (davesc63)

**Repository**: https://github.com/davesc63/GeoPort

- Built with Python, Flask, and pymobiledevice3
- Web-based UI (not native macOS)
- Focuses on static location spoofing (teleportation)
- **Does NOT have joystick or movement features**
- Good reference for pymobiledevice3 integration patterns

### iToolab AnyGo (Commercial)

- Full joystick control at bottom-left of screen
- WASD and arrow key support
- One-stop and multi-stop route modes
- Speed control slider
- Cooldown timer for Pokemon Go
- Direction changes in real-time via joystick
- **Proprietary -- no source code available**

### Xcode's Built-in Location Simulation

- Predefined movement routes: City Run, City Bicycle Ride, Freeway Drive
- These are GPX files that cycle through waypoints
- **City Run speed**: ~3 m/s (jogging)
- **City Bicycle Ride speed**: ~5-6 m/s (moderate cycling)
- **Freeway Drive speed**: ~25-30 m/s (highway)
- Update rate: Based on GPX timestamp intervals (typically 1 Hz)

### pymobiledevice3's Built-in GPX Playback

From the source code we examined:

```python
class LocationSimulationBase:
    def play_gpx_file(self, filename, disable_sleep=False, timing_randomness_range=0):
        # Parses GPX, iterates through points
        # Calls self.set(lat, lon) for each point
        # Sleeps between points based on GPX timestamps
        # timing_randomness_range adds +/- ms of random noise to timing
```

- No rate limiting between `set()` calls
- When `disable_sleep=True`, calls `set()` as fast as the channel allows
- `timing_randomness_range` in ms (e.g., 500 = +/- 500ms random delay)
- This proves the DVT channel can handle rapid sequential updates

---

## 7. Potential Issues & Anti-Spoofing <a name="7-potential-issues"></a>

### DVT Channel Stability Under Rapid Updates

**Will rapid location updates cause errors or disconnects?**

Based on research:

- **No documented errors** from rapid `set()` calls in pymobiledevice3 issues
- The `play_gpx_file(disable_sleep=True)` mode sends updates as fast as possible with no reported problems
- The DVT channel is a persistent connection designed for continuous instrument data flow
- **Potential concern**: If the Python bridge's stdin/stdout gets backed up with rapid commands, the JSON-line protocol could experience buffering issues. Mitigation: use fire-and-forget sends or batch updates.

**Recommendation**: Start with 1 Hz updates. If stable, optionally allow 2-4 Hz for smoother movement.

### iOS Behavior with Rapid Location Changes

**How does CoreLocation handle rapid simulated location changes?**

- CoreLocation's `locationd` daemon receives the simulated coordinates directly
- It does NOT apply smoothing or filtering -- the simulated location replaces the GPS fix immediately
- `CLLocation.speed` is NOT automatically computed from position deltas during simulation (per issue #340 -- speed, heading, altitude are not settable)
- Apps that compute speed from `location.speed` will see 0 or -1 (invalid)
- Apps that compute speed from consecutive position deltas will see whatever our movement engine produces
- **No inherent iOS-level smoothing** that would fight against our updates

### Battery / CPU Impact

**On the iPhone:**
- Location simulation through DVT bypasses the GPS hardware -- the radio is not used
- `locationd` processes the injected coordinates, but this is lightweight
- Apps consuming location data behave normally (same CPU as with real GPS)
- **Battery impact is minimal** -- possibly less than real GPS since the radio isn't active

**On the Mac:**
- The Python bridge process uses minimal CPU for relaying JSON commands
- DVT channel maintenance is lightweight (TCP keepalive)
- Timer running at 1 Hz is negligible
- **Total Mac CPU impact**: Negligible

### App-Level Anti-Spoofing Detection

**General detection techniques used by apps:**

| Technique | How It Works | Risk Level for Our Tool |
|-----------|-------------|----------------------|
| **Sensor mismatch** | Compare accelerometer/gyroscope data with GPS movement | **Medium** -- device is physically stationary while "moving" |
| **Speed/distance consistency** | Check if speed changes are physically possible | **Low** if using realistic speeds |
| **Timestamp gaps** | Look for irregular update intervals | **Low** with consistent 1 Hz updates |
| **Horizontal accuracy** | Simulated location may report different accuracy | **Low** -- locationd reports normal accuracy values |
| **Location history jumps** | Detect teleportation (impossible speed between two points) | **Low** if starting from real location and moving gradually |
| **IP geolocation mismatch** | Compare GPS location with IP-based location | **Medium** -- depends on user's actual location |
| **Jailbreak/root detection** | Check for Cydia, modified system files | **None** -- our approach doesn't jailbreak |
| **CLLocationSourceInformation** | iOS 15+ flag: `isSimulatedBySoftware` | **Varies** -- pymobiledevice3 may or may not trigger this |

### Pokemon Go Specific Speed Limits

| Activity | Speed Limit | Effect |
|----------|------------|--------|
| Egg hatching / Adventure Sync | 10.5 km/h (2.9 m/s) | Distance stops counting above this |
| Incense spawns | 15 km/h (4.2 m/s) | Optimal spawn rate below this |
| Speed lock warning | 35 km/h (9.7 m/s) | "You're going too fast" popup |
| Gameplay lock | 60+ km/h | Pokemon flee, stops don't work |
| Cooldown (teleport) | Distance-based | 2 min (1 km) to 120 min (1500+ km) |

**To avoid Pokemon Go detection:**
- Keep speed at or below 2.9 m/s (10.5 km/h)
- Don't teleport -- always "walk" between locations
- Add slight speed variation (+/- 10%)
- Pause occasionally (real walkers stop at intersections, etc.)
- The joystick should allow fine speed control within this range

### General Anti-Detection Best Practices

1. **Start from the device's real location** -- don't teleport to a new city
2. **Use walking speed** (1.0-1.4 m/s) for safest behavior
3. **1 Hz update rate** matches real GPS hardware
4. **Gradual direction changes** -- don't spin 180 degrees instantly
5. **Occasional stops** -- real people stop walking periodically
6. **Consistent speed** within mode -- don't oscillate wildly
7. **Avoid perfectly straight lines** -- add very slight randomness to heading (+/- 1-2 degrees)

---

## 8. Practical Recommendations for AutoLocation <a name="8-recommendations"></a>

### Phase 1: Core Movement Engine

1. **Create a `MovementEngine` class** (`@Observable`) that manages:
   - Current simulated position (lat/lon)
   - Current bearing (degrees)
   - Current speed (m/s)
   - Speed mode (walk/run/cycle/drive)
   - Update timer (1 Hz)
   - Movement state (stopped/moving)

2. **Timer loop at 1 Hz**: Each tick calculates new position using the bearing-distance formula and sends `set_location` to the bridge. Use the simplified coordinate math (good for <1km moves).

3. **No bridge protocol changes needed initially**: Reuse the existing `set_location` command. The persistent DVT session handles repeated calls efficiently.

### Phase 2: Input Controls

4. **Virtual joystick**: Custom SwiftUI view using `DragGesture`. Map displacement angle to bearing, magnitude to speed (0-100% of mode speed). Place in the bottom-left of the sidebar or as a floating panel.

5. **Keyboard controls**: Add `.onKeyPress()` handler for WASD/arrows. Track active directions, combine into bearing vector. Hold-to-move with `.down` and `.up` phases.

6. **Speed mode buttons**: Segmented control or buttons for Walk/Run/Cycle/Drive. Each sets the `speedMode` which determines max speed.

### Phase 3: Map Integration

7. **Click-to-walk**: Click on map to set a destination. Calculate bearing from current position to destination. Start walking at selected speed. Stop when within 2m of destination.

8. **Heading indicator**: Show current bearing as an arrow/triangle on the map at the simulated position.

9. **Movement path trail**: Optionally show the path taken as a polyline on the map.

### Phase 4: Polish

10. **GPS jitter option**: Toggle to add +/- 2-3m random noise.
11. **Speed display**: Show current speed in selected units (m/s or km/h).
12. **Distance traveled counter**: Running total since movement started.
13. **Bearing display**: Compass direction + degrees.

### Key Technical Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Update frequency | 1 Hz | Matches real GPS, safe for anti-spoofing |
| Timer runs in | Swift (MovementEngine) | Simpler architecture, bridge stays stateless |
| Coordinate math | Simplified approximation | Accurate enough for <1km steps, fast |
| Bridge communication | Reuse `set_location` | No protocol changes needed |
| Joystick library | Custom (50 lines) | No dependency, full control |
| Keyboard handling | SwiftUI `.onKeyPress()` | Native, simple, macOS 14+ |
| Input response | Direct (no acceleration) | Simpler; acceleration is optional polish |

### Estimated Implementation Effort

| Component | Estimated Lines | Complexity |
|-----------|----------------|------------|
| MovementEngine | ~150 | Medium |
| JoystickView | ~80 | Low |
| KeyboardHandler | ~60 | Low |
| Speed mode UI | ~40 | Low |
| Click-to-walk | ~80 | Medium |
| Heading indicator | ~30 | Low |
| Integration (wiring) | ~100 | Medium |
| **Total** | **~540** | **Medium** |

---

## Sources

### pymobiledevice3
- [pymobiledevice3 GitHub Repository](https://github.com/doronz88/pymobiledevice3)
- [Issue #340 - Simulate location with speed, heading and altitude](https://github.com/doronz88/pymobiledevice3/issues/340)
- [Issue #572 - Unreliable simulate-location with iOS 17](https://github.com/doronz88/pymobiledevice3/issues/572)
- [Issue #767 - DVT simulate-location doesn't self exit](https://github.com/doronz88/pymobiledevice3/issues/767)
- [Issue #975 - LocationSimulation InvalidServiceError](https://github.com/doronz88/pymobiledevice3/issues/975)
- [pymobiledevice3 on PyPI](https://pypi.org/project/pymobiledevice3/)
- [pymobiledevice3 DeepWiki](https://deepwiki.com/doronz88/pymobiledevice3)

### Coordinate Math
- [Movable Type - Calculate distance and bearing](https://www.movable-type.co.uk/scripts/latlong.html)
- [Haversine Formula - Wikipedia](https://en.wikipedia.org/wiki/Haversine_formula)
- [USGS - Distance per degree](https://www.usgs.gov/faqs/how-much-distance-does-a-degree-minute-and-second-cover-your-maps)
- [Preferred Walking Speed - Wikipedia](https://en.wikipedia.org/wiki/Preferred_walking_speed)

### SwiftUI Joystick / Input
- [SwiftUIJoystick Library](https://github.com/michael94ellis/SwiftUIJoystick)
- [Among Us Joystick Gist](https://gist.github.com/shial4/c6d163c7d12174d817a53b8c8e83b3b8)
- [Hacking with Swift - Key Press Events](https://www.hackingwithswift.com/quick-start/swiftui/how-to-detect-and-respond-to-key-press-events)
- [SwiftLee - Key Press Events Detection](https://www.avanderlee.com/swiftui/key-press-events-detection/)
- [macOS Game Keyboard Input](https://blog.bitbebop.com/macos-game-keyboard-input/)
- [DragGesture - SwiftUI Handbook](https://designcode.io/swiftui-handbook-drag-gesture/)

### Existing Location Simulation Tools
- [LocationSimulator (Schlaubischlump)](https://github.com/Schlaubischlump/LocationSimulator)
- [LocationSpoofer Swift Package](https://github.com/Schlaubischlump/LocationSpoofer)
- [GeoPort](https://github.com/davesc63/GeoPort)
- [SimVirtualLocation](https://github.com/nexron171/SimVirtualLocation)
- [pyioslocationsimulator](https://github.com/FButros/pyioslocationsimulator)

### Anti-Spoofing & Detection
- [Pokemon Go Walking Speed Limits](https://www.foneazy.com/tips/pokemon-go-walking-speed/)
- [Pokemon Go Speed Limit Hack](https://itoolab.com/location/pokemon-go-speed-limit/)
- [Detect Fake GPS Location iPhone](https://www.pogoskill.com/change-location/detect-fake-gps-location-iphone.html)
- [GPS Spoofing Detection using Accelerometers (MDPI)](https://www.mdpi.com/1424-8220/20/4/954)
- [Appdome - Detect Fake Location in iOS Apps](https://www.appdome.com/how-to/mobile-fraud-prevention-detection/geo-compliance/detect-gps-spoofing-in-ios-apps/)

### Apple Documentation
- [CLLocationManager Documentation](https://developer.apple.com/documentation/corelocation/cllocationmanager)
- [Energy Efficiency Guide - Location Best Practices](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html)
- [WWDC23 - Streamlined Location Updates](https://developer.apple.com/videos/play/wwdc2023/10180/)
- [SwiftUI Input Events](https://developer.apple.com/documentation/swiftui/input-events)
