# Route Planner Feature — Implementation Plan

## Goal
Let users draw custom paths on the map (series of waypoints), set speed, and have the app automatically simulate movement along the path.

## Data Model

### Route.swift (new)
```swift
struct Waypoint: Identifiable, Codable, Hashable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String?  // optional label
}

struct Route: Identifiable, Codable {
    let id: UUID
    var name: String
    var waypoints: [Waypoint]
}
```

### AppState additions
```swift
var routeWaypoints: [Waypoint] = []       // current route being edited/played
var isEditingRoute: Bool = false           // map tap adds waypoints
var isFollowingRoute: Bool = false         // simulation is running along route
var currentRouteWaypointIndex: Int = 0     // progress indicator
var shouldLoopRoute: Bool = false          // restart when finished
```

## Work Streams

### Stream 1: Model + Engine (MovementEngine)
- Create Route.swift
- Update AppState.swift with route state
- Add route following to MovementEngine:
  - `followRoute(waypoints:)` — starts walking through waypoints in order
  - In `tick()`, when arriving at a waypoint, auto-advance to next
  - Loop support
  - `stopRoute()` — cancels route following

### Stream 2: Map UI (MapContainerView)
- Show numbered waypoint markers when editing route
- Draw MapPolyline connecting waypoints
- When `isEditingRoute`, map tap adds waypoint instead of setting target
- Show current progress during simulation

### Stream 3: Sidebar UI (RouteEditorView section)
- New "Route Planner" GroupBox in SidebarView
- Toggle route editing mode
- Waypoint list with delete buttons
- Speed mode selector (reuse SpeedMode)
- Start/Stop route simulation button
- Loop toggle
- Clear all waypoints button
